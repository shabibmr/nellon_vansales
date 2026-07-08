import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/item.dart';
import '../../domain/models/route.dart';
import '../../domain/models/sales_invoice.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/cash_closing.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/models/salesperson.dart';
import '../../domain/models/payment_account.dart';
import '../../domain/models/tax.dart';
import '../../domain/models/expense_account.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/open_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/utils/stock_rules.dart';
import '../models/customer_model.dart';
import '../models/item_model.dart';
import '../models/sales_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sales_return_model.dart';
import '../models/expense_entry_model.dart';
import '../models/cash_closing_model.dart';
import '../models/warehouse_model.dart';
import '../models/salesperson_model.dart';
import '../models/payment_account_model.dart';
import '../models/tax_model.dart';
import '../models/expense_account_model.dart';
import '../models/organization_model.dart';
import '../models/open_invoice_model.dart';
import '../models/sales_order_model.dart';
import '../models/stock_transfer_model.dart';
import '../models/sync_queue_item.dart';

/// Database service backing the application's offline-first capabilities using Hive boxes.
///
/// Manages three distinct storage areas:
/// 1. `_masterBox`: Stores cached Zoho Books configurations, settings, items, and customer routes.
/// 2. `_syncQueueBox`: Manages sequential tasks/payloads waiting to sync when online.
/// 3. `_localHistoryBox`: Records locally created transactions instantly so UI displays them with zero latency.
class HiveDatabaseService {
  static const String _masterBoxName = 'master_data_box';
  static const String _syncQueueBoxName = 'sync_queue_box';
  static const String _localHistoryBoxName = 'local_history_box';

  late Box _masterBox;
  late Box _syncQueueBox;
  late Box _localHistoryBox;

  /// Lazily-built id-indexed cache backing [getCustomerById], invalidated
  /// whenever [saveCustomers] persists a new master list.
  Map<String, Customer>? _customerCache;

  /// Initializes the local database bindings and opens Hive boxes.
  Future<void> init() async {
    await Hive.initFlutter();
    _masterBox = await Hive.openBox(_masterBoxName);
    _syncQueueBox = await Hive.openBox(_syncQueueBoxName);
    _localHistoryBox = await Hive.openBox(_localHistoryBoxName);
  }

  /// Clears all local caches, queues, and transaction histories.
  Future<void> clearAll() async {
    await _masterBox.clear();
    await _syncQueueBox.clear();
    await _localHistoryBox.clear();
  }

  /// Gets the ID of the selected active delivery route.
  String? get activeRouteId => _masterBox.get('active_route_id');

  /// Saves the active delivery route ID.
  Future<void> setActiveRouteId(String? routeId) async {
    await _masterBox.put('active_route_id', routeId);
  }

  /// Gets the physical warehouse ID mapped to the van.
  String? get assignedWarehouseId => _masterBox.get('assigned_warehouse_id');

  /// Runtime override for unified mock/live transaction sync.
  /// When null, [ServerConfigCubit] derives mock mode from remote config.
  bool? get transactionMockModeEnabled =>
      _masterBox.get('transaction_mock_mode_enabled') as bool?;

  /// Persists the unified mock/live transaction sync preference on device.
  Future<void> setTransactionMockModeEnabled(bool enabled) async {
    await _masterBox.put('transaction_mock_mode_enabled', enabled);
  }

  /// Mapps a specific Zoho warehouse ID to this local van sales session.
  Future<void> setAssignedWarehouseId(String? warehouseId) async {
    await _masterBox.put('assigned_warehouse_id', warehouseId);
  }

  /// Retrieves the list of synced master customer records.
  List<Customer> getCustomers() {
    final rawList = _masterBox.get('customers', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => CustomerModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Saves or refreshes customer master lists.
  Future<void> saveCustomers(List<Customer> customers) async {
    final serialized = customers
        .map((c) => jsonEncode(CustomerModel.fromDomain(c).toJson()))
        .toList();
    await _masterBox.put('customers', serialized);
    _customerCache = null;
  }

  /// Looks up a single customer by id via an in-memory index built from
  /// [getCustomers], avoiding a full deserialize-and-scan on every call.
  Customer? getCustomerById(String id) {
    _customerCache ??= {for (final c in getCustomers()) c.id: c};
    return _customerCache![id];
  }

  /// Updates latitude/longitude for a specific customer (by id) and persists.
  /// If the customer is not found, this is a no-op.
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    final current = getCustomers();
    final index = current.indexWhere((c) => c.id == customerId);
    if (index < 0) return;

    final updated = current[index].copyWith(
      latitude: latitude,
      longitude: longitude,
    );
    final newList = List<Customer>.from(current);
    newList[index] = updated;
    await saveCustomers(newList);
  }

  /// Retrieves the list of synced master stocked inventory products.
  List<Item> getItems() {
    final rawList = _masterBox.get('items', defaultValue: []);
    return (rawList as List)
        .map(
          (item) =>
              ItemModel.fromJson(Map<String, dynamic>.from(jsonDecode(item))),
        )
        .toList();
  }

  /// Saves or refreshes inventory items list.
  Future<void> saveItems(List<Item> items) async {
    final serialized = items
        .map((i) => jsonEncode(ItemModel.fromDomain(i).toJson()))
        .toList();
    await _masterBox.put('items', serialized);
  }

  /// Retrieves the list of synced master routes.
  List<RouteModel> getRoutes() {
    final rawList = _masterBox.get('routes', defaultValue: []);
    return (rawList as List).map((item) {
      final decoded = Map<String, dynamic>.from(jsonDecode(item));
      return RouteModel(
        id: decoded['id'] ?? '',
        name: decoded['name'] ?? '',
        description: decoded['description'] ?? '',
      );
    }).toList();
  }

  /// Saves master delivery routes list.
  Future<void> saveRoutes(List<RouteModel> routes) async {
    final serialized = routes
        .map(
          (r) => jsonEncode({
            'id': r.id,
            'name': r.name,
            'description': r.description,
          }),
        )
        .toList();
    await _masterBox.put('routes', serialized);
  }

  /// Retrieves list of synced warehouses.
  List<Warehouse> getWarehouses() {
    final rawList = _masterBox.get('warehouses', defaultValue: []);
    return (rawList as List)
        .map(
          (w) =>
              WarehouseModel.fromJson(Map<String, dynamic>.from(jsonDecode(w))),
        )
        .toList();
  }

  /// Saves master warehouses list.
  Future<void> saveWarehouses(List<Warehouse> warehouses) async {
    final serialized = warehouses
        .map((w) => jsonEncode(WarehouseModel.fromDomain(w).toJson()))
        .toList();
    await _masterBox.put('warehouses', serialized);
  }

  /// Retrieves the master list of all synced Zoho Books salespersons (sales users).
  List<Salesperson> getSalespersons() {
    final rawList = _masterBox.get('salespersons', defaultValue: []);
    return (rawList as List)
        .map(
          (s) => SalespersonModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(s)),
          ),
        )
        .toList();
  }

  /// Saves or refreshes the master salespersons list.
  Future<void> saveSalespersons(List<Salesperson> salespersons) async {
    final serialized = salespersons
        .map((s) => jsonEncode(SalespersonModel.fromDomain(s).toJson()))
        .toList();
    await _masterBox.put('salespersons', serialized);
  }

  /// Retrieves the resolved salesperson record for the currently logged-in session, if any.
  Salesperson? getCurrentSalesperson() {
    final raw = _masterBox.get('current_salesperson');
    if (raw == null) return null;
    return SalespersonModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  /// Caches the resolved active salesperson for the current session.
  Future<void> saveCurrentSalesperson(Salesperson salesperson) async {
    await _masterBox.put(
      'current_salesperson',
      jsonEncode(SalespersonModel.fromDomain(salesperson).toJson()),
    );
  }

  /// Retrieves payment/bank ledgers for receipt mapping.
  List<PaymentAccount> getPaymentAccounts() {
    final rawList = _masterBox.get('payment_accounts', defaultValue: []);
    return (rawList as List)
        .map(
          (a) => PaymentAccountModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(a)),
          ),
        )
        .toList();
  }

  /// Saves synced deposit payment accounts/ledgers.
  Future<void> savePaymentAccounts(List<PaymentAccount> accounts) async {
    final serialized = accounts
        .map((a) => jsonEncode(PaymentAccountModel.fromDomain(a).toJson()))
        .toList();
    await _masterBox.put('payment_accounts', serialized);
  }

  /// Retrieves the list of synced VAT/Tax configurations.
  List<Tax> getTaxes() {
    final rawList = _masterBox.get('taxes', defaultValue: []);
    return (rawList as List)
        .map((t) => TaxModel.fromJson(Map<String, dynamic>.from(jsonDecode(t))))
        .toList();
  }

  /// Saves synced tax brackets.
  Future<void> saveTaxes(List<Tax> taxes) async {
    final serialized = taxes
        .map((t) => jsonEncode(TaxModel.fromDomain(t).toJson()))
        .toList();
    await _masterBox.put('taxes', serialized);
  }

  /// Retrieves list of synced expense account ledgers.
  List<ExpenseAccount> getExpenseAccounts() {
    final rawList = _masterBox.get('expense_accounts', defaultValue: []);
    return (rawList as List)
        .map(
          (a) => ExpenseAccountModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(a)),
          ),
        )
        .toList();
  }

  /// Saves synced expense ledgers.
  Future<void> saveExpenseAccounts(List<ExpenseAccount> accounts) async {
    final serialized = accounts
        .map((a) => jsonEncode(ExpenseAccountModel.fromDomain(a).toJson()))
        .toList();
    await _masterBox.put('expense_accounts', serialized);
  }

  /// Retrieves active Organization configurations.
  Organization? getOrganization() {
    final raw = _masterBox.get('organization');
    if (raw == null) return null;
    return OrganizationModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  /// Caches active Organization configurations.
  Future<void> saveOrganization(Organization org) async {
    await _masterBox.put(
      'organization',
      jsonEncode(OrganizationModel.fromDomain(org).toJson()),
    );
  }

  /// Retrieves synced outstanding customer invoices snapshot.
  ///
  /// Optionally filters outstanding invoices down to a specific [customerId].
  List<OpenInvoice> getOpenInvoices({String? customerId}) {
    final rawList = _masterBox.get('open_invoices', defaultValue: []);
    final all = (rawList as List)
        .map(
          (i) => OpenInvoiceModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(i)),
          ),
        )
        .toList();
    if (customerId == null) return all;
    return all.where((inv) => inv.customerId == customerId).toList();
  }

  /// Overwrites current cached unpaid invoices snapshot.
  Future<void> saveOpenInvoices(List<OpenInvoice> invoices) async {
    final serialized = invoices
        .map((i) => jsonEncode(OpenInvoiceModel.fromDomain(i).toJson()))
        .toList();
    await _masterBox.put('open_invoices', serialized);
  }

  /// Retrieves a list of all sequential tasks awaiting synchronization.
  List<SyncQueueItem> getSyncQueue() {
    final keys = _syncQueueBox.keys.toList();
    return keys.map((key) {
      final raw = _syncQueueBox.get(key);
      return SyncQueueItem.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    }).toList();
  }

  /// Enqueues a new background task to the synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    await _syncQueueBox.put(item.id, jsonEncode(item.toJson()));
  }

  /// Re-saves a task to update its execution status or failure logs.
  Future<void> updateSyncItem(SyncQueueItem item) async {
    await _syncQueueBox.put(item.id, jsonEncode(item.toJson()));
  }

  /// Deletes a task from the queue once it has successfully synchronised.
  Future<void> dequeueSyncItem(String id) async {
    await _syncQueueBox.delete(id);
  }

  /// Permanently removes every queue task currently marked [SyncStatus.failed].
  ///
  /// Pending and syncing items are left untouched so unsynced work is never
  /// silently discarded — only tasks that have already exhausted a sync
  /// attempt and failed are cleared.
  Future<void> clearFailedSyncItems() async {
    for (final item in getSyncQueue()) {
      if (item.status == SyncStatus.failed) {
        await _syncQueueBox.delete(item.id);
      }
    }
  }

  /// Filters a list of location-taggable records down to the active session location.
  ///
  /// Records with no `locationId` (legacy, pre-dating this field) always pass through.
  /// When no location is active for the session, no filtering is applied.
  List<T> _filterByActiveLocation<T>(
    List<T> items,
    String? Function(T) locationIdOf,
  ) {
    final active = assignedWarehouseId;
    if (active == null) return items;
    return items
        .where((i) => locationIdOf(i) == null || locationIdOf(i) == active)
        .toList();
  }

  /// Retrieves the full, unfiltered list of invoices recorded locally (for internal read-modify-write use).
  List<SalesInvoice> _getAllLocalInvoices() {
    final rawList = _localHistoryBox.get('invoices', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => SalesInvoiceModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of invoices recorded locally, scoped to the active session location.
  List<SalesInvoice> getLocalInvoices() =>
      _filterByActiveLocation(_getAllLocalInvoices(), (inv) => inv.locationId);

  /// Caches a newly created sales invoice locally and immediately updates corresponding item stock level in the van.
  ///
  /// Validates stock *before* persisting anything: if any line would drive an
  /// item's stock below zero, this throws [InsufficientStockException] and
  /// neither the invoice nor the stock levels are written — the invoice can
  /// never be committed while silently leaving stock inconsistent.
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    final stamped = invoice.locationId == null && assignedWarehouseId != null
        ? invoice.copyWith(locationId: assignedWarehouseId)
        : invoice;
    final current = _getAllLocalInvoices();
    final model = SalesInvoiceModel.fromDomain(stamped);

    final index = current.indexWhere((inv) => inv.id == stamped.id);
    final oldInvoice = index >= 0 ? current[index] : null;

    // Compute (and validate) the resulting item stock levels before writing
    // anything: restore the old invoice's quantities (if this is an edit),
    // then deduct the new invoice's quantities, enforcing the single
    // stock invariant via deductStock().
    final localItems = getItems();
    if (oldInvoice != null) {
      for (final line in oldInvoice.items) {
        final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
        if (itemIndex >= 0) {
          final existingItem = localItems[itemIndex];
          localItems[itemIndex] = existingItem.copyWith(
            stock: existingItem.stock + line.quantity,
          );
        }
      }
    }
    for (final line in stamped.items) {
      final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
      if (itemIndex >= 0) {
        final existingItem = localItems[itemIndex];
        final updatedStock = deductStock(
          itemId: existingItem.id,
          itemName: existingItem.name,
          available: existingItem.stock,
          requested: line.quantity,
        );
        localItems[itemIndex] = existingItem.copyWith(stock: updatedStock);
      }
    }

    // Stock validation passed — now persist the invoice and the updated stock.
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }
    final serialized = current
        .map((inv) => jsonEncode(SalesInvoiceModel.fromDomain(inv).toJson()))
        .toList();
    await _localHistoryBox.put('invoices', serialized);
    await saveItems(localItems);
  }

  /// Retrieves the full, unfiltered list of sales orders recorded locally (for internal read-modify-write use).
  List<SalesOrder> _getAllLocalOrders() {
    final rawList = _localHistoryBox.get('sales_orders', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => SalesOrderModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of sales orders recorded locally, scoped to the active session location.
  List<SalesOrder> getLocalOrders() =>
      _filterByActiveLocation(_getAllLocalOrders(), (ord) => ord.locationId);

  /// Caches a newly created sales order locally.
  ///
  /// Note: Unlike Sales Invoices, creating a Sales Order does not directly deduct physical inventory stock levels immediately.
  Future<void> saveLocalOrder(SalesOrder order) async {
    final stamped = order.locationId == null && assignedWarehouseId != null
        ? order.copyWith(locationId: assignedWarehouseId)
        : order;
    final current = _getAllLocalOrders();
    final model = SalesOrderModel.fromDomain(stamped);

    // Add or update
    final index = current.indexWhere((ord) => ord.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((ord) => jsonEncode(SalesOrderModel.fromDomain(ord).toJson()))
        .toList();
    await _localHistoryBox.put('sales_orders', serialized);
  }

  /// Merges a freshly downloaded set of remote sales orders into the local cache.
  ///
  /// Offline-first rule: orders still awaiting their first sync (`isPendingSync`) are
  /// preserved untouched; everything else is replaced by the authoritative remote set.
  /// Remote orders are matched against local ones by `zohoOrderId` to avoid duplicates.
  Future<void> saveRemoteOrders(List<SalesOrder> remote) async {
    final pendingLocal = _getAllLocalOrders()
        .where((o) => o.isPendingSync)
        .toList();

    // Drop any pending-local order that the remote set already accounts for.
    final remoteIds = remote.map((o) => o.id).toSet();
    final keptLocal = pendingLocal
        .where(
          (o) => o.zohoOrderId == null || !remoteIds.contains(o.zohoOrderId),
        )
        .toList();

    final merged = [...keptLocal, ...remote];
    final serialized = merged
        .map((ord) => jsonEncode(SalesOrderModel.fromDomain(ord).toJson()))
        .toList();
    await _localHistoryBox.put('sales_orders', serialized);
  }

  /// Retrieves the full, unfiltered list of stock transfers recorded locally (for internal read-modify-write use).
  List<StockTransfer> _getAllLocalStockTransfers() {
    final rawList = _localHistoryBox.get('stock_transfers', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => StockTransferModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of stock transfers (Issue to Van / Stock Unloading) recorded
  /// locally, scoped to the active session location.
  List<StockTransfer> getLocalStockTransfers() => _filterByActiveLocation(
    _getAllLocalStockTransfers(),
    (t) => t.locationId,
  );

  /// Caches a newly created stock transfer locally and adjusts the van's local
  /// item stock levels: [StockTransferDirection.load] increases stock (Issue
  /// to Van), [StockTransferDirection.unload] decreases it (Stock Unloading).
  ///
  /// Validates stock *before* persisting anything: an unload that would drive
  /// an item's stock below zero throws [InsufficientStockException] and
  /// neither the transfer record nor the stock levels are written — mirrors
  /// the invariant enforced by [saveLocalInvoice].
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {
    final stamped =
        transfer.locationId == null && assignedWarehouseId != null
        ? transfer.copyWith(locationId: assignedWarehouseId)
        : transfer;

    // Compute (and validate) the resulting item stock levels before writing anything.
    final localItems = getItems();
    for (final line in stamped.lines) {
      final itemIndex = localItems.indexWhere((it) => it.id == line.item.id);
      if (itemIndex < 0) continue;
      final existingItem = localItems[itemIndex];
      final updatedStock = stamped.direction == StockTransferDirection.load
          ? existingItem.stock + line.quantity
          : deductStock(
              itemId: existingItem.id,
              itemName: existingItem.name,
              available: existingItem.stock,
              requested: line.quantity,
            );
      localItems[itemIndex] = existingItem.copyWith(stock: updatedStock);
    }

    // Stock validation passed — now persist the transfer record and the updated stock.
    final current = _getAllLocalStockTransfers();
    final model = StockTransferModel.fromDomain(stamped);

    final index = current.indexWhere((t) => t.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((t) => jsonEncode(StockTransferModel.fromDomain(t).toJson()))
        .toList();
    await _localHistoryBox.put('stock_transfers', serialized);
    await saveItems(localItems);
  }

  /// Retrieves the full, unfiltered list of receipts recorded locally (for internal read-modify-write use).
  List<ReceiptVoucher> _getAllLocalReceipts() {
    final rawList = _localHistoryBox.get('receipts', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => ReceiptVoucherModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves all collection receipts recorded locally, scoped to the active session location.
  List<ReceiptVoucher> getLocalReceipts() =>
      _filterByActiveLocation(_getAllLocalReceipts(), (rec) => rec.locationId);

  /// Caches a newly created receipt locally and instantly decrements the matching customer's outstanding balance in memory.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    final stamped = voucher.locationId == null && assignedWarehouseId != null
        ? voucher.copyWith(locationId: assignedWarehouseId)
        : voucher;
    final current = _getAllLocalReceipts();
    final model = ReceiptVoucherModel.fromDomain(stamped);

    final index = current.indexWhere((rec) => rec.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((rec) => jsonEncode(ReceiptVoucherModel.fromDomain(rec).toJson()))
        .toList();
    await _localHistoryBox.put('receipts', serialized);

    // Adjust local Customer outstanding balance instantly!
    final localCustomers = getCustomers();
    final customerIndex = localCustomers.indexWhere(
      (cust) => cust.id == voucher.customerId,
    );
    if (customerIndex >= 0) {
      final existingCust = localCustomers[customerIndex];
      final updatedBalance = existingCust.outstandingBalance - voucher.amount;
      localCustomers[customerIndex] = existingCust.copyWith(
        outstandingBalance: updatedBalance >= 0 ? updatedBalance : 0.0,
      );
    }
    await saveCustomers(localCustomers);
  }

  /// Retrieves the full, unfiltered list of sales returns recorded locally (for internal read-modify-write use).
  List<SalesReturn> _getAllLocalReturns() {
    final rawList = _localHistoryBox.get('returns', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => SalesReturnModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves list of sales returns recorded locally, scoped to the active session location.
  List<SalesReturn> getLocalReturns() =>
      _filterByActiveLocation(_getAllLocalReturns(), (ret) => ret.locationId);

  /// Caches a sales return locally and immediately restores returned product stock levels back in the local inventory.
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    final stamped =
        salesReturn.locationId == null && assignedWarehouseId != null
        ? salesReturn.copyWith(locationId: assignedWarehouseId)
        : salesReturn;
    final current = _getAllLocalReturns();
    final model = SalesReturnModel.fromDomain(stamped);

    final index = current.indexWhere((ret) => ret.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((ret) => jsonEncode(SalesReturnModel.fromDomain(ret).toJson()))
        .toList();
    await _localHistoryBox.put('returns', serialized);

    // Restore stock in local cached inventory instantly!
    final localItems = getItems();
    for (final line in stamped.items) {
      final itemIndex = localItems.indexWhere(
        (it) => it.id == line.invoiceLineItem.item.id,
      );
      if (itemIndex >= 0) {
        final existingItem = localItems[itemIndex];
        localItems[itemIndex] = existingItem.copyWith(
          stock: existingItem.stock + line.returnedQuantity,
        );
      }
    }
    await saveItems(localItems);
  }

  /// Retrieves the full, unfiltered list of expenses recorded locally (for internal read-modify-write use).
  List<ExpenseEntry> _getAllLocalExpenses() {
    final rawList = _localHistoryBox.get('expenses', defaultValue: []);
    return (rawList as List)
        .map(
          (item) => ExpenseEntryModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(item)),
          ),
        )
        .toList();
  }

  /// Retrieves all Filed route expenses, scoped to the active session location.
  List<ExpenseEntry> getLocalExpenses() =>
      _filterByActiveLocation(_getAllLocalExpenses(), (exp) => exp.locationId);

  /// Caches a new expense voucher locally.
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    final stamped = expense.locationId == null && assignedWarehouseId != null
        ? expense.copyWith(locationId: assignedWarehouseId)
        : expense;
    final current = _getAllLocalExpenses();
    final model = ExpenseEntryModel.fromDomain(stamped);

    final index = current.indexWhere((exp) => exp.id == stamped.id);
    if (index >= 0) {
      current[index] = model;
    } else {
      current.insert(0, model);
    }

    final serialized = current
        .map((exp) => jsonEncode(ExpenseEntryModel.fromDomain(exp).toJson()))
        .toList();
    await _localHistoryBox.put('expenses', serialized);
  }

  /// Retrieves the end-of-trip daily cash closing record, if filed.
  CashClosing? getLocalCashClosing() {
    final raw = _localHistoryBox.get('cash_closing');
    if (raw == null) return null;
    return CashClosingModel.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw)),
    );
  }

  /// Caches the daily cash closing reconciliation record.
  Future<void> saveLocalCashClosing(CashClosing closing) async {
    final model = CashClosingModel.fromDomain(closing);
    await _localHistoryBox.put('cash_closing', jsonEncode(model.toJson()));
  }

  /// True if there's recorded sales activity (invoices, receipts, or
  /// expenses) dated today, but no cash-closing reconciliation has been
  /// filed for today — i.e. the day-close workflow is still outstanding.
  ///
  /// Used to gate logout so a day's activity can't be walked away from
  /// without reconciling cash in hand against expected takings.
  bool hasPendingCashClosingForToday() {
    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final hasActivityToday =
        getLocalInvoices().any((inv) => isToday(inv.date)) ||
        getLocalReceipts().any((rec) => isToday(rec.date)) ||
        getLocalExpenses().any((exp) => isToday(exp.date));
    if (!hasActivityToday) return false;

    final closing = getLocalCashClosing();
    return closing == null || !isToday(closing.date);
  }

  /// Gets the cached OAuth 2.0 Access Token for Zoho Books.
  String? get oauthAccessToken => _masterBox.get('oauth_access_token');

  /// Saves the cached OAuth 2.0 Access Token for Zoho Books.
  Future<void> setOauthAccessToken(String? token) async {
    await _masterBox.put('oauth_access_token', token);
  }

  /// Gets the token expiry timestamp in milliseconds.
  int? get oauthTokenExpiry => _masterBox.get('oauth_token_expiry');

  /// Saves the token expiry timestamp in milliseconds.
  Future<void> setOauthTokenExpiry(int? expiryMillis) async {
    await _masterBox.put('oauth_token_expiry', expiryMillis);
  }
}
