import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'hive_database_service.dart';
import 'zoho_api_client.dart';
import '../models/sync_queue_item.dart';
import '../models/item_model.dart';
import '../models/customer_model.dart';
import '../../domain/models/route.dart';

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

      // Re-trigger a fetch of master data so localized cache has all remote records updated
      await refreshMasterData();

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

  // 2. Fetch fresh Master Data from Zoho Books (Customers, Items, Routes)
  Future<void> refreshMasterData() async {
    final activeRoute = _dbService.activeRouteId;
    final activeWarehouse = _dbService.assignedWarehouseId ?? 'van_wh_01';

    try {
      // Fetch routes
      final routeList = await _apiClient.fetchRoutes();
      final domainRoutes = routeList.map((r) => RouteModel(
        id: r['id'],
        name: r['name'],
        description: r['description'],
      )).toList();
      await _dbService.saveRoutes(domainRoutes);

      // Fetch items for our warehouse
      final itemList = await _apiClient.fetchItems(activeWarehouse);
      final domainItems = itemList.map((i) => ItemModel.fromJson(i)).toList();
      await _dbService.saveItems(domainItems);

      // Fetch customers for our active route (if selected)
      if (activeRoute != null && activeRoute.isNotEmpty) {
        final customerList = await _apiClient.fetchCustomers(activeRoute);
        final domainCustomers = customerList.map((c) => CustomerModel.fromJson(c)).toList();
        await _dbService.saveCustomers(domainCustomers);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error refreshing master data from Zoho Books: $e');
    }
  }
}
