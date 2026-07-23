import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'app_logger.dart';
import 'document_number_service.dart';
import 'error_classification.dart';
import 'hive_database_service.dart';
import 'zoho_api_client.dart';
import '../models/sync_queue_item.dart';
import '../models/item_model.dart';
import '../models/customer_model.dart';
import '../models/warehouse_model.dart';
import '../models/salesperson_model.dart';
import '../models/payment_account_model.dart';
import '../models/tax_model.dart';
import '../models/expense_account_model.dart';
import '../models/organization_model.dart';
import '../../domain/models/route.dart';

/// Enumerates master/reference data configurations synced from the backend.
///
/// **Transactions are never included** (invoices, receipts, sales orders,
/// returns, expenses). Those are pushed via the offline queue and, when needed
/// for UI (e.g. open balances), fetched live from Zoho — never bulk-synced
/// from the Sync Masters page.
enum MasterType {
  /// General organization settings (Currency symbols, names, formatting context).
  organization,

  /// Synced Zoho Books warehouses/van compartments.
  warehouses,

  /// Deposit ledger accounts maps for receipts.
  paymentAccounts,

  /// Organization Tax configurations.
  taxes,

  /// Ledger expense ledger accounts.
  expenseAccounts,

  /// Configured delivery routes list.
  routes,

  /// Inventory items with rates and van stock quantities.
  items,

  /// Customer entities.
  customers,

  /// Master list of all Zoho Books salespersons (sales users).
  salespersons,
}

/// Extension providing human-readable labels for master datatypes.
extension MasterTypeLabel on MasterType {
  /// Gets a readable description category label.
  String get label {
    switch (this) {
      case MasterType.organization:
        return 'Organization';
      case MasterType.warehouses:
        return 'Warehouses';
      case MasterType.paymentAccounts:
        return 'Payment Accounts';
      case MasterType.taxes:
        return 'Taxes';
      case MasterType.expenseAccounts:
        return 'Expense Accounts';
      case MasterType.routes:
        return 'Routes';
      case MasterType.items:
        return 'Items';
      case MasterType.customers:
        return 'Customers';
      case MasterType.salespersons:
        return 'Salespersons';
    }
  }
}

/// The core offline synchronisation engine of the application.
///
/// Runs background listeners to automatically push transactions to the Zoho Books server
/// whenever the device regains a network connection.
/// Tracks sync statistics and manages dependency resolution during uploads.
class SyncWorker {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;
  final DocumentNumberService _numberService;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;

  final _syncStatusController = StreamController<String>.broadcast();

  /// Broadcast stream communicating structural progress status text (e.g. "Syncing Invoice...").
  Stream<String> get syncStatusStream => _syncStatusController.stream;

  final _syncCountController = StreamController<int>.broadcast();

  /// Broadcast stream indicating the remaining count of unsynced queue tasks.
  Stream<int> get syncCountStream => _syncCountController.stream;

  bool _isSyncing = false;

  /// Returns true if a background sync sequence is actively running.
  bool get isSyncing => _isSyncing;

  /// Instantiates a new [SyncWorker] background controller.
  ///
  /// Installs network change connectivity listeners to automatically fire syncs when regaining access.
  /// [checkConnectivity] can be overridden (e.g. with a fake) in tests; when
  /// overridden, the live connectivity-change auto-resync listener (which
  /// talks to the real platform channel) is skipped, since `Connectivity` is
  /// a non-subclassable singleton and tests have no platform channel to back it.
  Timer? _autoRetryTimer;

  SyncWorker({
    required HiveDatabaseService dbService,
    required ZohoApiClient apiClient,
    DocumentNumberService? numberService,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
  }) : _dbService = dbService,
       _apiClient = apiClient,
       _numberService = numberService ??
           DocumentNumberService(dbService: dbService, apiClient: apiClient),
       _checkConnectivity =
           checkConnectivity ?? Connectivity().checkConnectivity {
    if (checkConnectivity == null) {
      // Listen to network changes
      Connectivity().onConnectivityChanged.listen((
        List<ConnectivityResult> results,
      ) {
        if (results.any((r) => r != ConnectivityResult.none)) {
          syncPendingItems();
        }
      });

      // Periodically re-check whether any transient-failed item's backoff
      // window has elapsed, so retries happen automatically while the app
      // stays online rather than only on reconnect or a manual tap.
      _autoRetryTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => syncPendingItems(),
      );
    }
  }

  /// Disposes the periodic auto-retry timer, if one was started.
  void dispose() {
    _autoRetryTimer?.cancel();
  }

  /// Exponential backoff delay for a failed item's [retryCount]-th retry:
  /// 30s, 1m, 2m, 4m, 8m, capped at 30 minutes.
  static Duration _backoffDelay(int retryCount) {
    final seconds = 30 * (1 << retryCount.clamp(0, 6));
    return Duration(seconds: seconds.clamp(30, 1800));
  }

  /// Iterates through the pending local transaction queue and pushes items sequentially.
  ///
  /// Relational dependency management:
  /// - Sorts the queue to ensure newly created offline Customers are synced first.
  /// - Captures newly assigned Zoho IDs from successful customer creations.
  /// - Automatically scans subsequent queued transactions (invoices, receipts) and replaces
  ///   their temporary local client customer IDs with the permanent Zoho Contacts ID.
  ///
  /// By default (e.g. called from the connectivity listener or the periodic
  /// auto-retry timer), failed items are only retried if they were
  /// classified as transient (see `error_classification.dart`) AND their
  /// exponential backoff window has elapsed — a permanent (validation)
  /// failure won't be retried automatically since it can't succeed without a
  /// data fix. Pass [forceRetryAll] (from the manual "Retry Failed" UI
  /// action) to bypass both checks and retry every failed item immediately.
  Future<void> syncPendingItems({bool forceRetryAll = false}) async {
    if (_isSyncing) return;

    final connectivityResult = await _checkConnectivity();
    if (connectivityResult.any((r) => r == ConnectivityResult.none)) {
      _syncStatusController.add('Offline: No Internet Connection');
      return;
    }

    final now = DateTime.now();
    final queue = _dbService.getSyncQueue();
    final activeItems = queue
        .where((item) => item.status != SyncStatus.completed)
        .toList();

    if (activeItems.isEmpty) {
      _syncStatusController.add('All transactions are synced');
      _syncCountController.add(0);
      return;
    }

    final pendingItems = activeItems.where((item) {
      if (item.status != SyncStatus.failed || forceRetryAll) return true;

      // Auto-retry path: skip permanent failures and anything still within
      // its backoff window.
      final isPermanent =
          item.errorMessage?.startsWith('[Needs Attention]') ?? false;
      if (isPermanent) return false;
      final nextRetryAt = item.timestamp.add(_backoffDelay(item.retryCount));
      return !now.isBefore(nextRetryAt);
    }).toList();

    if (pendingItems.isEmpty) {
      // Items remain unsynced, but none are eligible to run right now
      // (still in backoff, or waiting on a permanent-failure fix) — leave
      // the count/status as-is rather than falsely reporting "all synced".
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
        // Re-read this item's current persisted state rather than trusting
        // the batch snapshot taken before the loop started: if an earlier
        // item in this same batch was a customer/sales-order whose sync
        // just patched a temp id into this item's payload (see
        // _resolveTempCustomerIdsInQueue / _resolveTempOrderIdsInQueue),
        // the stale snapshot would still carry the old temp id and this
        // item would sync against the wrong reference.
        var item = _dbService.getSyncQueue().firstWhere(
          (q) => q.id == pendingItems[i].id,
          orElse: () => pendingItems[i],
        );
        _syncStatusController.add(
          'Syncing ${i + 1}/${pendingItems.length}: ${item.type.toUpperCase()}...',
        );

        // Mark as syncing in Hive
        await _dbService.updateSyncItem(
          item.copyWith(status: SyncStatus.syncing),
        );

        var renumberAttemptsLeft = 2;
        while (true) {
          try {
            await _dispatchSync(item);

            // Mark completed and remove from queue
            await _dbService.dequeueSyncItem(item.id);
            successCount++;
            break;
          } catch (e) {
            final docType = _docTypeForItemType(item.type);
            if (docType != null &&
                renumberAttemptsLeft > 0 &&
                _isDuplicateNumberError(e)) {
              renumberAttemptsLeft--;
              try {
                item = await _renumberAndPersist(item, docType);
                continue;
              } catch (renumberError) {
                AppLogger.error(
                  'Sync',
                  'Renumber failed for item ${item.id}: $renumberError',
                );
              }
            }

            final category = classifySyncError(e);
            AppLogger.error(
              'Sync',
              'Sync error on item ${item.id} ($category): $e',
            );
            // Mark failed and cache error logs, tagging the message with the
            // error category so the Sync Queue UI can distinguish "retryable"
            // failures from ones needing manual attention.
            final tag = category == ErrorCategory.transient
                ? '[Retryable]'
                : '[Needs Attention]';
            await _dbService.updateSyncItem(
              item.copyWith(
                status: SyncStatus.failed,
                errorMessage: '$tag $e',
                // Anchor exponential backoff to this attempt, not the item's
                // original creation time.
                timestamp: DateTime.now(),
                retryCount: item.retryCount + 1,
              ),
            );
            break;
          }
        }
      }

      _syncStatusController.add(
        successCount == pendingItems.length
            ? 'Sync Successful: All transactions synced!'
            : 'Sync Partial: $successCount/${pendingItems.length} synced successfully.',
      );

      if (successCount == pendingItems.length) {
        unawaited(_numberService.seedCounters());
      }
    } finally {
      _isSyncing = false;
      _syncCountController.add(
        _dbService
            .getSyncQueue()
            .where((x) => x.status != SyncStatus.completed)
            .length,
      );
    }
  }

  /// Dispatches [item] to the matching `ZohoApiClient.syncX` call and runs
  /// the type-specific post-success side effects (temp-id resolution etc.).
  Future<void> _dispatchSync(SyncQueueItem item) async {
    switch (item.type) {
      case 'customer':
        final remoteId = await _apiClient.syncCustomer(item.payload);
        // CRITICAL: Replace temporary offline customer ID with permanent Zoho ID in all subsequent queue items!
        await _resolveTempCustomerIdsInQueue(item.id, remoteId);
      case 'customer_gps_update':
        // Lightweight GPS enrichment update (contact must already exist in Zoho)
        final cid =
            item.payload['contact_id']?.toString() ??
            item.payload['customer_id']?.toString();
        final lat = (item.payload['latitude'] as num?)?.toDouble();
        final lng = (item.payload['longitude'] as num?)?.toDouble();
        if (cid != null && lat != null && lng != null) {
          await _apiClient.updateCustomerGps(cid, lat, lng);
        }
      case 'invoice':
        await _apiClient.syncInvoice(item.payload);
      case 'sales_order':
        final remoteId = await _apiClient.syncSalesOrder(item.payload);
        // Persist the permanent Zoho salesorder_id on the local order and
        // patch any pending conversion so it can target the real id.
        await _persistOrderZohoId(item.id, remoteId);
        await _resolveTempOrderIdsInQueue(item.id, remoteId);
      case 'update_sales_order':
        final remoteId = await _apiClient.updateSalesOrder(
          item.payload['salesorder_id'],
          item.payload,
        );
        await _persistOrderZohoId(item.id, remoteId);
      case 'convert_so':
        await _apiClient.convertSalesOrderToInvoice(
          item.payload['salesorder_id'],
        );
      case 'receipt':
        await _apiClient.syncReceiptVoucher(item.payload);
      case 'return':
        await _apiClient.syncSalesReturn(item.payload);
      case 'expense':
        await _apiClient.syncExpense(item.payload);
      case 'stock_transfer':
        await _apiClient.syncStockTransfer(item.payload);
      default:
        throw Exception('Unsupported transaction sync type: ${item.type}');
    }
  }

  /// Maps a queue item's [type] to the [DocType] whose offline counter it
  /// consumes, or null for types with no app-side numbering (customers,
  /// expenses, stock transfers, GPS updates, order updates/conversions).
  DocType? _docTypeForItemType(String type) {
    switch (type) {
      case 'invoice':
        return DocType.invoice;
      case 'sales_order':
        return DocType.salesOrder;
      case 'receipt':
        return DocType.receipt;
      case 'return':
        return DocType.creditNote;
      default:
        return null;
    }
  }

  /// The stored payload key holding the app-generated document number for a
  /// queue item [type] with a [_docTypeForItemType] match.
  String? _numberKeyForItemType(String type) {
    switch (type) {
      case 'invoice':
        return 'invoice_number';
      case 'sales_order':
        return 'salesorder_number';
      case 'receipt':
        return 'payment_number';
      case 'return':
        return 'creditnote_number';
      default:
        return null;
    }
  }

  /// Whether [e] represents a Zoho "document number already exists" rejection.
  ///
  /// The client wraps Dio failures into plain `Exception` strings today, so
  /// this matches on Zoho's duplicate-number error code (4062) or common
  /// wording. TODO: rethrow the underlying `DioException` from the `syncX`
  /// methods so this can inspect `error.response?.data['code']` directly.
  bool _isDuplicateNumberError(Object e) {
    final message = e.toString().toLowerCase();
    return message.contains('"code":4062') ||
        message.contains('code: 4062') ||
        (message.contains('number') &&
            (message.contains('already exists') ||
                message.contains('already been used') ||
                message.contains('has already been taken')));
  }

  /// Re-seeds [docType]'s counter, rewrites [item]'s number key (and receipt
  /// `reference_number`) to the fresh value, persists the queue item, and
  /// patches the matching local-history record so printed/browsed history
  /// stays in sync with what was actually pushed to Zoho.
  Future<SyncQueueItem> _renumberAndPersist(
    SyncQueueItem item,
    DocType docType,
  ) async {
    final newNumber = await _numberService.reseedAndNext(docType);
    final numberKey = _numberKeyForItemType(item.type)!;
    final updatedPayload = Map<String, dynamic>.from(item.payload);
    updatedPayload[numberKey] = newNumber;
    if (item.type == 'receipt') {
      updatedPayload['reference_number'] = newNumber;
    }

    final updated = item.copyWith(
      payload: updatedPayload,
      status: SyncStatus.syncing,
    );
    await _dbService.updateSyncItem(updated);
    await _patchLocalHistoryNumber(item.type, item.id, newNumber);
    return updated;
  }

  /// Patches the locally-cached record's display number to match a
  /// post-renumber payload, so PDFs/history lists never show a stale number
  /// that Zoho rejected.
  Future<void> _patchLocalHistoryNumber(
    String type,
    String localId,
    String newNumber,
  ) async {
    switch (type) {
      case 'invoice':
        final invoices = _dbService.getLocalInvoices();
        final index = invoices.indexWhere((i) => i.id == localId);
        if (index >= 0) {
          await _dbService.saveLocalInvoice(
            invoices[index].copyWith(invoiceNumber: newNumber),
          );
        }
      case 'sales_order':
        final orders = _dbService.getLocalOrders();
        final index = orders.indexWhere((o) => o.id == localId);
        if (index >= 0) {
          await _dbService.saveLocalOrder(
            orders[index].copyWith(orderNumber: newNumber),
          );
        }
      case 'receipt':
        final receipts = _dbService.getLocalReceipts();
        final index = receipts.indexWhere((r) => r.id == localId);
        if (index >= 0) {
          await _dbService.saveLocalReceipt(
            receipts[index].copyWith(paymentNumber: newNumber),
          );
        }
      case 'return':
        final returns = _dbService.getLocalReturns();
        final index = returns.indexWhere((r) => r.id == localId);
        if (index >= 0) {
          await _dbService.saveLocalReturn(
            returns[index].copyWith(creditNoteNumber: newNumber),
          );
        }
    }
  }

  /// Scans the unsynced queue payload maps and swaps out temporary customer keys with permanent server IDs.
  Future<void> _resolveTempCustomerIdsInQueue(
    String tempCustomerId,
    String permanentZohoId,
  ) async {
    final currentQueue = _dbService.getSyncQueue();
    for (final item in currentQueue) {
      if (item.status == SyncStatus.pending ||
          item.status == SyncStatus.failed) {
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
          await _dbService.updateSyncItem(
            item.copyWith(payload: updatedPayload),
          );
        }
      }
    }
  }

  /// Stores the permanent Zoho `salesorder_id` on the local order record once synced,
  /// so a later conversion can target the real id.
  Future<void> _persistOrderZohoId(
    String localOrderId,
    String zohoOrderId,
  ) async {
    final orders = _dbService.getLocalOrders();
    final index = orders.indexWhere((o) => o.id == localOrderId);
    if (index >= 0) {
      await _dbService.saveLocalOrder(
        orders[index].copyWith(zohoOrderId: zohoOrderId, isPendingSync: false),
      );
    }
  }

  /// Patches any pending/failed `convert_so` queue items whose `salesorder_id`
  /// still points at the temporary local order id, swapping in the permanent Zoho id.
  Future<void> _resolveTempOrderIdsInQueue(
    String tempOrderId,
    String permanentZohoId,
  ) async {
    final currentQueue = _dbService.getSyncQueue();
    for (final item in currentQueue) {
      if (item.type != 'convert_so') continue;
      if (item.status == SyncStatus.pending ||
          item.status == SyncStatus.failed) {
        if (item.payload['salesorder_id'] == tempOrderId) {
          final updatedPayload = Map<String, dynamic>.from(item.payload);
          updatedPayload['salesorder_id'] = permanentZohoId;
          await _dbService.updateSyncItem(
            item.copyWith(payload: updatedPayload),
          );
        }
      }
    }
  }

  /// Fetches a specific configuration master from the Zoho Books REST endpoints and updates local Hive boxes.
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
          await _dbService.saveRoutes(
            list
                .map(
                  (r) => RouteModel(
                    id: r['id'],
                    name: r['name'],
                    description: r['description'],
                  ),
                )
                .toList(),
          );
          break;
        case MasterType.items:
          final activeWarehouse = _dbService.assignedWarehouseId ?? 'van_wh_01';
          final list = await _apiClient.fetchItems(activeWarehouse);
          // Multi-UOM (`unit_conversions`) is intentionally NOT downloaded here.
          // The /items LIST endpoint never returns it, so it is fetched lazily
          // and cached per-item the first time an item is selected from Item
          // Search (see SalesRepository.resolveItemUnitConversions).
          await _dbService.saveItems(
            list.map((i) => ItemModel.fromJson(i)).toList(),
          );
          break;
        case MasterType.customers:
          final list = await _apiClient.fetchCustomers();
          await _dbService.saveCustomers(
            list.map((c) => CustomerModel.fromJson(c)).toList(),
          );
          break;
        case MasterType.salespersons:
          final list = await _apiClient.fetchSalespersons();
          await _dbService.saveSalespersons(
            list.map((s) => SalespersonModel.fromJson(s)).toList(),
          );
          break;
      }
      _syncStatusController.add('${type.label} synced.');
    } catch (e) {
      _syncStatusController.add('${type.label} sync failed: $e');
      rethrow;
    }
  }

  /// Triggers a full, sequential download of all configurations, settings, items, and route listings.
  Future<void> refreshMasterData() async {
    _syncStatusController.add('Refreshing master data...');
    for (final type in MasterType.values) {
      try {
        await syncMaster(type);
      } catch (_) {
        // Per-master errors already surfaced; continue with the rest.
      }
    }
    _syncStatusController.add('Master data refresh complete.');
  }
}
