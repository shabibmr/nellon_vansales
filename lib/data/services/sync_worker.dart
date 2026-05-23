import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'hive_database_service.dart';
import 'zoho_api_client.dart';
import '../models/sync_queue_item.dart';
import '../models/item_model.dart';
import '../models/customer_model.dart';
import '../models/warehouse_model.dart';
import '../models/payment_account_model.dart';
import '../models/tax_model.dart';
import '../models/expense_account_model.dart';
import '../models/organization_model.dart';
import '../models/open_invoice_model.dart';
import '../../domain/models/route.dart';

enum MasterType {
  organization,
  warehouses,
  paymentAccounts,
  taxes,
  expenseAccounts,
  routes,
  items,
  customers,
  openInvoices,
}

extension MasterTypeLabel on MasterType {
  String get label {
    switch (this) {
      case MasterType.organization:    return 'Organization';
      case MasterType.warehouses:      return 'Warehouses';
      case MasterType.paymentAccounts: return 'Payment Accounts';
      case MasterType.taxes:           return 'Taxes';
      case MasterType.expenseAccounts: return 'Expense Accounts';
      case MasterType.routes:          return 'Routes';
      case MasterType.items:           return 'Items';
      case MasterType.customers:       return 'Customers';
      case MasterType.openInvoices:    return 'Open Invoices';
    }
  }
}

class SyncWorker {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;
  final Connectivity _connectivity = Connectivity();
  
  final _syncStatusController = StreamController<String>.broadcast();
  Stream<String> get syncStatusStream => _syncStatusController.stream;

  final _syncCountController = StreamController<int>.broadcast();
  Stream<int> get syncCountStream => _syncCountController.stream;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  SyncWorker({
    required HiveDatabaseService this._dbService,
    required ZohoApiClient this._apiClient,
  }) {
    // Listen to network changes
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        syncPendingItems();
      }
    });
  }

  Future<void> syncPendingItems() async {
    if (_isSyncing) return;

    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.any((r) => r == ConnectivityResult.none)) {
      _syncStatusController.add('Offline: No Internet Connection');
      return;
    }

    final queue = _dbService.getSyncQueue();
    final pendingItems = queue.where((item) => item.status != SyncStatus.completed).toList();

    if (pendingItems.isEmpty) {
      _syncStatusController.add('All transactions are synced');
      _syncCountController.add(0);
      return;
    }

    _isSyncing = true;
    _syncStatusController.add('Sync starting...');
    _syncCountController.add(pendingItems.length);

    try {
      // 1. Sort queue so "customers" sync first (relational dependency)
      pendingItems.sort((a, b) {
        if (a.type == 'customer' && b.type != 'customer') return -1;
        if (a.type != 'customer' && b.type == 'customer') return 1;
        return a.timestamp.compareTo(b.timestamp);
      });

      int successCount = 0;
      for (int i = 0; i < pendingItems.length; i++) {
        final item = pendingItems[i];
        _syncStatusController.add('Syncing ${i + 1}/${pendingItems.length}: ${item.type.toUpperCase()}...');
        
        // Mark as syncing in Hive
        await _dbService.updateSyncItem(item.copyWith(status: SyncStatus.syncing));

        try {
          String remoteId = '';
          switch (item.type) {
            case 'customer':
              remoteId = await _apiClient.syncCustomer(item.payload);
              // CRITICAL: Replace temporary offline customer ID with permanent Zoho ID in all subsequent queue items!
              await _resolveTempCustomerIdsInQueue(item.id, remoteId);
              break;
            case 'invoice':
              remoteId = await _apiClient.syncInvoice(item.payload);
              break;
            case 'receipt':
              remoteId = await _apiClient.syncReceiptVoucher(item.payload);
              break;
            case 'return':
              remoteId = await _apiClient.syncSalesReturn(item.payload);
              break;
            case 'expense':
              remoteId = await _apiClient.syncExpense(item.payload);
              break;
            default:
              throw Exception('Unsupported transaction sync type: ${item.type}');
          }

          // Mark completed and remove from queue
          await _dbService.dequeueSyncItem(item.id);
          successCount++;
        } catch (e) {
          // ignore: avoid_print
          print('Sync error on item ${item.id}: $e');
          // Mark failed and cache error logs
          await _dbService.updateSyncItem(item.copyWith(
            status: SyncStatus.failed,
            errorMessage: e.toString(),
          ));
        }
      }

      _syncStatusController.add(successCount == pendingItems.length
          ? 'Sync Successful: All transactions synced!'
          : 'Sync Partial: $successCount/${pendingItems.length} synced successfully.');
    } finally {
      _isSyncing = false;
      _syncCountController.add(_dbService.getSyncQueue().where((x) => x.status != SyncStatus.completed).length);
    }
  }

  // Helper: Relational Integrity ID Updater
  Future<void> _resolveTempCustomerIdsInQueue(String tempCustomerId, String permanentZohoId) async {
    final currentQueue = _dbService.getSyncQueue();
    for (final item in currentQueue) {
      if (item.status == SyncStatus.pending || item.status == SyncStatus.failed) {
        bool modified = false;
        final updatedPayload = Map<String, dynamic>.from(item.payload);

        // Update customerId fields
        if (updatedPayload['customer_id'] == tempCustomerId) {
          updatedPayload['customer_id'] = permanentZohoId;
          modified = true;
        }
        if (updatedPayload['customerId'] == tempCustomerId) {
          updatedPayload['customerId'] = permanentZohoId;
          modified = true;
        }

        if (modified) {
          await _dbService.updateSyncItem(item.copyWith(payload: updatedPayload));
        }
      }
    }
  }

  // Fetch a single master from Zoho Books and save into Hive.
  Future<void> syncMaster(MasterType type) async {
    _syncStatusController.add('Syncing ${type.label}...');
    try {
      switch (type) {
        case MasterType.organization:
          final org = await _apiClient.fetchOrganization();
          if (org != null) {
            await _dbService.saveOrganization(OrganizationModel.fromJson(org));
          }
          break;
        case MasterType.warehouses:
          final list = await _apiClient.fetchWarehouses();
          await _dbService.saveWarehouses(
            list.map((w) => WarehouseModel.fromJson(w)).toList(),
          );
          break;
        case MasterType.paymentAccounts:
          final list = await _apiClient.fetchPaymentAccounts();
          await _dbService.savePaymentAccounts(
            list.map((a) => PaymentAccountModel.fromJson(a)).toList(),
          );
          break;
        case MasterType.taxes:
          final list = await _apiClient.fetchTaxes();
          await _dbService.saveTaxes(
            list.map((t) => TaxModel.fromJson(t)).toList(),
          );
          break;
        case MasterType.expenseAccounts:
          final list = await _apiClient.fetchExpenseAccounts();
          await _dbService.saveExpenseAccounts(
            list.map((a) => ExpenseAccountModel.fromJson(a)).toList(),
          );
          break;
        case MasterType.routes:
          final list = await _apiClient.fetchRoutes();
          await _dbService.saveRoutes(list
              .map((r) => RouteModel(
                    id: r['id'],
                    name: r['name'],
                    description: r['description'],
                  ))
              .toList());
          break;
        case MasterType.items:
          final activeWarehouse = _dbService.assignedWarehouseId ?? 'van_wh_01';
          final list = await _apiClient.fetchItems(activeWarehouse);
          await _dbService.saveItems(
            list.map((i) => ItemModel.fromJson(i)).toList(),
          );
          break;
        case MasterType.customers:
          final activeRoute = _dbService.activeRouteId;
          if (activeRoute == null || activeRoute.isEmpty) {
            throw Exception('No active route selected');
          }
          final list = await _apiClient.fetchCustomers(activeRoute);
          await _dbService.saveCustomers(
            list.map((c) => CustomerModel.fromJson(c)).toList(),
          );
          break;
        case MasterType.openInvoices:
          final list = await _apiClient.fetchOpenInvoices();
          await _dbService.saveOpenInvoices(
            list.map((i) => OpenInvoiceModel.fromJson(i)).toList(),
          );
          break;
      }
      _syncStatusController.add('${type.label} synced.');
    } catch (e) {
      _syncStatusController.add('${type.label} sync failed: $e');
      rethrow;
    }
  }

  // Pull all masters that don't require an active route/warehouse selection.
  // Items/customers are pulled here too when the selection exists.
  Future<void> refreshMasterData() async {
    _syncStatusController.add('Refreshing master data...');
    for (final type in MasterType.values) {
      if (type == MasterType.customers && (_dbService.activeRouteId == null || _dbService.activeRouteId!.isEmpty)) {
        continue;
      }
      try {
        await syncMaster(type);
      } catch (_) {
        // Per-master errors already surfaced; continue with the rest.
      }
    }
    _syncStatusController.add('Master data refresh complete.');
  }
}
