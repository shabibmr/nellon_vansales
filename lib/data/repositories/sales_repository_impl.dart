import '../../domain/models/route.dart';
import '../../domain/models/customer.dart';
import '../models/customer_model.dart';
import '../../domain/models/customer_ledger.dart';
import '../../domain/models/item.dart';
import '../../domain/models/organization.dart';
import '../../domain/models/sales_invoice.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/cash_closing.dart';
import '../../domain/models/open_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/models/unit_conversion.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/repositories/sales_repository.dart';
import '../models/sync_queue_item.dart';
import '../models/unit_conversion_model.dart';
import '../services/app_logger.dart';
import '../models/item_model.dart';
import '../models/sales_order_model.dart';
import '../models/sales_invoice_model.dart';
import '../models/receipt_voucher_model.dart';
import '../models/sales_return_model.dart';
import '../models/expense_entry_model.dart';
import '../models/stock_transfer_model.dart';
import '../models/open_invoice_model.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SalesRepository] backed by a local Hive database cache.
///
/// Implements swift read/write interfaces utilizing [HiveDatabaseService] for fast offline performance.
class SalesRepositoryImpl implements SalesRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  /// Creates a new [SalesRepositoryImpl] wrapping the Hive local database provider.
  SalesRepositoryImpl({required this._dbService, required this._apiClient});

  @override
  List<RouteModel> getRoutes() => _dbService.getRoutes();

  @override
  String? get activeRouteId => _dbService.activeRouteId;

  @override
  Future<void> setActiveRouteId(String? routeId) =>
      _dbService.setActiveRouteId(routeId);

  @override
  List<Customer> getCustomers() => _dbService.getCustomers();

  @override
  Future<void> saveCustomers(List<Customer> customers) =>
      _dbService.saveCustomers(customers);

  @override
  List<Item> getItems() => _dbService.getItems();

  @override
  Future<void> saveItems(List<Item> items) => _dbService.saveItems(items);

  @override
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(
    Item item,
  ) async {
    // Already enriched (e.g. carried on an existing line item) — nothing to do.
    if (item.unitConversions.isNotEmpty) {
      return (item: item, offlineFallback: false);
    }

    // Previously resolved: serve from the dedicated item-UOM box. A cached but
    // empty entry means "checked, none exist" — still short-circuits the fetch.
    if (_dbService.hasItemUnitConversions(item.id)) {
      final cached = _dbService.getItemUnitConversions(item.id);
      final resolved =
          cached.isEmpty ? item : item.copyWith(unitConversions: cached);
      return (item: resolved, offlineFallback: false);
    }

    // First selection while (hopefully) online — the /items list endpoint never
    // returns unit_conversions, so fetch the item detail once and cache it.
    try {
      final detail = await _apiClient.fetchItemDetail(item.id);
      final conversions =
          (detail['unit_conversions'] as List<dynamic>? ?? const [])
              .map(
                (c) => UnitConversionModel.fromJson(
                  Map<String, dynamic>.from(c as Map),
                ) as UnitConversion,
              )
              .toList();
      // Persist even when empty so we don't re-hit Zoho for this item.
      await _dbService.saveItemUnitConversions(item.id, conversions);
      final resolved = conversions.isEmpty
          ? item
          : item.copyWith(unitConversions: conversions);
      return (item: resolved, offlineFallback: false);
    } catch (e) {
      // Offline / rate-limited / any failure: fall back to base-unit-only and
      // do NOT cache, so a later online selection retries the fetch.
      AppLogger.error(
        'SalesRepository',
        'resolveItemUnitConversions(${item.id}) error: $e',
      );
      return (item: item, offlineFallback: true);
    }
  }

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  ) async {
    final id = customer.id.trim();
    if (id.isEmpty || id.startsWith('temp_')) {
      return (customer: customer, offlineFallback: false);
    }

    Customer merge(Customer base, {required String trn, required String address}) {
      return base.copyWith(
        trn: base.trn.trim().isNotEmpty ? base.trn : trn,
        address: base.address.trim().isNotEmpty ? base.address : address,
      );
    }

    if (customer.trn.trim().isNotEmpty) {
      return (customer: customer, offlineFallback: false);
    }

    if (_dbService.hasCustomerDetail(id)) {
      final cached = _dbService.getCustomerDetail(id)!;
      return (
        customer: merge(customer, trn: cached.trn, address: cached.address),
        offlineFallback: false,
      );
    }

    try {
      final detail = await _apiClient.fetchContactDetail(id);
      final parsed = CustomerModel.fromJson(detail);
      final trn = parsed.trn.trim();
      final address = parsed.address.trim();
      await _dbService.saveCustomerDetail(id, trn: trn, address: address);
      final resolved = merge(customer, trn: trn, address: address);
      await _dbService.upsertCustomer(resolved);
      return (customer: resolved, offlineFallback: false);
    } catch (e) {
      AppLogger.error(
        'SalesRepository',
        'resolveCustomerDetails($id) error: $e',
      );
      return (customer: customer, offlineFallback: true);
    }
  }

  @override
  List<SalesInvoice> getLocalInvoices() => _dbService.getLocalInvoices();

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) =>
      _dbService.saveLocalInvoice(invoice);

  @override
  Future<SalesInvoice?> fetchInvoiceById(
    String invoiceId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (invoiceId.isEmpty) return null;
    SalesInvoice? local;
    for (final inv in _dbService.getAllLocalInvoicesUnfiltered()) {
      if (inv.id == invoiceId || inv.zohoInvoiceId == invoiceId) {
        local = inv;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    final remoteId = _remoteVoucherId(invoiceId, local?.zohoInvoiceId);
    if (remoteId == null) {
      if (allowOfflineFallback && local != null) return local;
      return local;
    }

    try {
      final json = await _apiClient.fetchInvoiceDetail(remoteId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _invoiceFromZoho(json);
      await _dbService.saveRemoteInvoices([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Header-only list path (no per-invoice detail). Full line items load
    // lazily via [fetchInvoiceById] when the editor opens.
    final raw = await _apiClient.fetchInvoiceHeaders(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final invoices = raw.map((json) {
      final inv = _invoiceFromZoho(json);
      if (vanId == null || vanId.isEmpty) return inv;
      return inv.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteInvoices(invoices);
    return _dbService.getLocalInvoices();
  }

  /// Zoho header `location_id` is org primary, not van warehouse — see
  /// [_orderFromZoho].
  SalesInvoice _invoiceFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['zoho_invoice_id'] = json['invoice_id'];
    map.remove('location_id');
    return SalesInvoiceModel.fromJson(map);
  }

  /// Zoho never accepts a local `temp_*` id. Prefer the persisted Zoho id,
  /// then a non-temp requested id; otherwise the caller must stay offline.
  String? _remoteVoucherId(String requestedId, String? zohoId) {
    if (zohoId != null && zohoId.isNotEmpty) return zohoId;
    if (requestedId.startsWith('temp_')) return null;
    return requestedId;
  }

  @override
  Future<ReceiptVoucher?> fetchReceiptById(
    String paymentId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (paymentId.isEmpty) return null;
    ReceiptVoucher? local;
    for (final rec in _dbService.getAllLocalReceiptsUnfiltered()) {
      if (rec.id == paymentId || rec.zohoPaymentId == paymentId) {
        local = rec;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    final remoteId = _remoteVoucherId(paymentId, local?.zohoPaymentId);
    if (remoteId == null) {
      if (allowOfflineFallback && local != null) return local;
      return local;
    }

    try {
      final json = await _apiClient.fetchReceiptDetail(remoteId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _receiptFromZoho(json);
      await _dbService.saveRemoteReceipts([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  @override
  Future<SalesReturn?> fetchSalesReturnById(
    String creditNoteId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (creditNoteId.isEmpty) return null;
    SalesReturn? local;
    for (final ret in _dbService.getAllLocalReturnsUnfiltered()) {
      if (ret.id == creditNoteId || ret.zohoCreditNoteId == creditNoteId) {
        local = ret;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    final remoteId = _remoteVoucherId(creditNoteId, local?.zohoCreditNoteId);
    if (remoteId == null) {
      if (allowOfflineFallback && local != null) return local;
      return local;
    }

    try {
      final json = await _apiClient.fetchSalesReturnDetail(remoteId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _returnFromZoho(json);
      await _dbService.saveRemoteReturns([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  @override
  Future<ExpenseEntry?> fetchExpenseById(
    String expenseId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (expenseId.isEmpty) return null;
    ExpenseEntry? local;
    for (final exp in _dbService.getAllLocalExpensesUnfiltered()) {
      if (exp.id == expenseId || exp.zohoExpenseId == expenseId) {
        local = exp;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    final remoteId = _remoteVoucherId(expenseId, local?.zohoExpenseId);
    if (remoteId == null) {
      if (allowOfflineFallback && local != null) return local;
      return local;
    }

    try {
      final json = await _apiClient.fetchExpenseDetail(remoteId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _expenseFromZoho(json);
      await _dbService.saveRemoteExpenses([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  /// Zoho header `location_id` is org primary, not van warehouse — see
  /// [_orderFromZoho].
  ExpenseEntry _expenseFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['zoho_expense_id'] = json['expense_id'];
    map.remove('location_id');
    return ExpenseEntryModel.fromZohoJson(map);
  }

  @override
  List<SalesOrder> getLocalOrders() => _dbService.getLocalOrders();

  @override
  Future<void> saveLocalOrder(SalesOrder order) =>
      _dbService.saveLocalOrder(order);

  @override
  Future<void> enqueueSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  }) async {
    final payload = SalesOrderModel.fromDomain(order).toJson();
    if (isUpdate) {
      final zohoId = order.zohoOrderId;
      if (zohoId != null && zohoId.isNotEmpty) {
        payload['salesorder_id'] = zohoId;
      }
    }
    await _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: order.id,
        type: isUpdate ? 'update_sales_order' : 'sales_order',
        payload: payload,
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueInvoice(SalesInvoice invoice) {
    return _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: invoice.id,
        type: 'invoice',
        payload: SalesInvoiceModel.fromDomain(invoice).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueConvertSalesOrder({
    required SalesOrder order,
    required SalesInvoice invoice,
  }) {
    return _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: invoice.id,
        type: 'convert_so',
        payload: {
          'salesorder_id': order.zohoOrderId ?? order.id,
          'source_order_id': order.id,
          'local_invoice_id': invoice.id,
        },
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueReceipt(ReceiptVoucher voucher) {
    return _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: voucher.id,
        type: 'receipt',
        payload: _receiptQueuePayload(voucher),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueSalesReturn(SalesReturn salesReturn) {
    return _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: salesReturn.id,
        type: 'return',
        payload: _returnQueuePayload(salesReturn),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueExpense(ExpenseEntry expense) {
    return _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: expense.id,
        type: 'expense',
        payload: ExpenseEntryModel.fromDomain(expense).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> enqueueStockTransfer(StockTransfer transfer) {
    return _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: transfer.id,
        type: 'stock_transfer',
        payload: StockTransferModel.fromDomain(transfer).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Receipt queue map with allocation invoice ids resolved to Zoho ids.
  Map<String, dynamic> _receiptQueuePayload(ReceiptVoucher voucher) {
    final payload = ReceiptVoucherModel.fromDomain(voucher).toJson();
    final invoices = payload['invoices'];
    if (invoices is! List) return payload;
    payload['invoices'] = invoices.map((entry) {
      if (entry is! Map) return entry;
      final map = Map<String, dynamic>.from(entry);
      final resolved = _resolvedInvoiceId(map['invoice_id']?.toString());
      if (resolved != null) map['invoice_id'] = resolved;
      return map;
    }).toList();
    return payload;
  }

  /// Credit-note queue map with line invoice ids resolved to Zoho ids.
  Map<String, dynamic> _returnQueuePayload(SalesReturn salesReturn) {
    final payload = SalesReturnModel.fromDomain(salesReturn).toJson();
    final lines = payload['line_items'];
    if (lines is! List) return payload;
    payload['line_items'] = lines.map((entry) {
      if (entry is! Map) return entry;
      final map = Map<String, dynamic>.from(entry);
      final resolved = _resolvedInvoiceId(map['invoice_id']?.toString());
      if (resolved != null) map['invoice_id'] = resolved;
      return map;
    }).toList();
    return payload;
  }

  /// Permanent Zoho invoice id when [localOrRemoteId] is a local temp id
  /// whose invoice has already synced; otherwise the original value.
  String? _resolvedInvoiceId(String? localOrRemoteId) {
    if (localOrRemoteId == null || localOrRemoteId.isEmpty) {
      return localOrRemoteId;
    }
    for (final inv in _dbService.getAllLocalInvoicesUnfiltered()) {
      if (inv.id == localOrRemoteId) {
        final zohoId = inv.zohoInvoiceId;
        if (zohoId != null && zohoId.isNotEmpty) return zohoId;
        return localOrRemoteId;
      }
    }
    return localOrRemoteId;
  }

  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchSalesOrders(
      startDate: startDate,
      endDate: endDate,
    );
    // Stamp with this session's van warehouse so [getLocalOrders] location
    // filter keeps them. Zoho header location_id is the org primary branch
    // (stripped in [_orderFromZoho]); without a van stamp, rows either stay
    // null (ok) or re-merge an old HQ id from Hive and disappear for every van.
    final vanId = _dbService.assignedWarehouseId;
    final orders = raw.map((json) {
      final order = _orderFromZoho(json);
      if (vanId == null || vanId.isEmpty) return order;
      return order.copyWith(locationId: vanId);
    }).toList();
    // List fetch is authoritative for the requested window: drop Hive rows
    // that fall in-range but are gone from Zoho (deleted remotely).
    await _dbService.saveRemoteOrders(
      orders,
      pruneMissingInRange: true,
      rangeStart: startDate,
      rangeEnd: endDate,
    );
    return _dbService.getLocalOrders();
  }

  @override
  Future<SalesOrder?> fetchRemoteOrder(
    String zohoOrderId, {
    bool allowOfflineFallback = false,
  }) async {
    SalesOrder? local;
    for (final o in _dbService.getLocalOrders()) {
      if (o.id == zohoOrderId || o.zohoOrderId == zohoOrderId) {
        local = o;
        break;
      }
    }
    try {
      final json = await _apiClient.fetchSalesOrder(zohoOrderId);
      if (json.isEmpty) {
        if (allowOfflineFallback) return local;
        return null;
      }
      final order = _orderFromZoho(json);
      await _dbService.saveRemoteOrders([order]);
      // Return the merged/patched cache entry, not the raw Zoho parse — the
      // raw parse never carries `locationId` (Zoho has no such field), while
      // saveRemoteOrders folds in whatever this device previously stamped.
      for (final o in _dbService.getLocalOrders()) {
        if (o.id == order.id) return o;
      }
      return order;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  /// Parses a Zoho `salesorder` envelope, stamping `zoho_order_id` from
  /// `salesorder_id`. Zoho never sends the former, so without this every
  /// downloaded order looks unsynced and an edit would be pushed as a *create*
  /// instead of `PUT /salesorders/{id}` (see SalesOrderEditorBloc save path). The
  /// stamp is done here, not in [SalesOrderModel.fromJson], because that
  /// factory also reads back local records whose `salesorder_id` is a
  /// `temp_so_…` id that Zoho has never seen.
  ///
  /// **location_id is not mapped.** Zoho's header `location_id` is the org
  /// primary / branch location (see [ZohoApiClient] Option B), not the van
  /// warehouse id used for on-device list scoping
  /// ([HiveDatabaseService.getLocalOrders]). Mapping it in caused remote
  /// orders (e.g. Test Customer) to save under HQ id and then disappear from
  /// every van session after `getLocalOrders` filtered them out.
  SalesOrder _orderFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['zoho_order_id'] = json['salesorder_id'];
    map.remove('location_id');
    return SalesOrderModel.fromJson(map);
  }

  @override
  List<ReceiptVoucher> getLocalReceipts() =>
      _sessionScopedReceipts(_dbService.getLocalReceipts());

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) =>
      _dbService.saveLocalReceipt(voucher);

  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchReceipts(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final receipts = raw.map((json) {
      final rec = _receiptFromZoho(json);
      if (vanId == null || vanId.isEmpty) return rec;
      return rec.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteReceipts(receipts);
    // API is already series-scoped; re-apply client-side so a polluted local
    // cache (pre-filter downloads) cannot surface other salesmen's receipts.
    return getLocalReceipts();
  }

  /// Zoho header `location_id` is org primary, not van warehouse — see
  /// [_orderFromZoho].
  ReceiptVoucher _receiptFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['zoho_payment_id'] = json['payment_id'];
    map.remove('location_id');
    return ReceiptVoucherModel.fromJson(map);
  }

  /// Keeps receipts whose app series number matches this session's
  /// `{voucherPrefix}RCT-` (stored as [ReceiptVoucher.paymentNumber] offline
  /// and as Zoho `reference_number` after sync). No prefix → unfiltered.
  List<ReceiptVoucher> _sessionScopedReceipts(List<ReceiptVoucher> all) {
    final prefix = _dbService.voucherPrefix?.trim();
    if (prefix == null || prefix.isEmpty) return all;
    final series = '${prefix}RCT-';
    return all
        .where(
          (r) =>
              r.paymentNumber.startsWith(series) ||
              r.referenceNumber.startsWith(series),
        )
        .toList();
  }

  @override
  List<SalesReturn> getLocalReturns() => _dbService.getLocalReturns();

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) =>
      _dbService.saveLocalReturn(salesReturn);

  @override
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Header-only list path (no per-return detail). Full line items load
    // lazily via [fetchSalesReturnById] when the editor opens.
    final raw = await _apiClient.fetchSalesReturnHeaders(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final returns = raw.map((json) {
      final ret = _returnFromZoho(json);
      if (vanId == null || vanId.isEmpty) return ret;
      return ret.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteReturns(returns);
    return _dbService.getLocalReturns();
  }

  /// Zoho header `location_id` is org primary, not van warehouse — see
  /// [_orderFromZoho].
  SalesReturn _returnFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['zoho_credit_note_id'] = json['creditnote_id'];
    map.remove('location_id');
    return SalesReturnModel.fromJson(map);
  }

  @override
  List<ExpenseEntry> getLocalExpenses() => _dbService.getLocalExpenses();

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) =>
      _dbService.saveLocalExpense(expense);

  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Header-only list path (no per-expense detail). Full line items load
    // lazily via [fetchExpenseById] when the editor opens.
    final raw = await _apiClient.fetchExpenseHeaders(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final remote = raw.map((json) {
      final exp = _expenseFromZoho(json);
      if (vanId == null || vanId.isEmpty) return exp;
      return exp.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteExpenses(remote);
    // Zoho scopes via paid_through_account_id; local cache is only
    // location-filtered and can still hold other salesmen's rows from older
    // unscoped pulls. Prefer the API set plus this device's pending drafts.
    final byId = <String, ExpenseEntry>{for (final e in remote) e.id: e};
    for (final local in _dbService.getLocalExpenses()) {
      if (local.isPendingSync) {
        byId.putIfAbsent(local.id, () => local);
      }
    }
    return byId.values.toList();
  }

  @override
  CashClosing? getLocalCashClosing() => _dbService.getLocalCashClosing();

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) =>
      _dbService.saveLocalCashClosing(closing);

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);

  @override
  List<SyncQueueItem> getSyncQueue() => _dbService.getSyncQueue();

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) =>
      _dbService.getOpenInvoices(customerId: customerId);

  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async {
    final raw = await _apiClient.fetchOpenInvoices(customerId: customerId);
    final list = raw.map((json) => OpenInvoiceModel.fromJson(json)).toList();

    if (customerId == null || customerId.isEmpty) {
      await _dbService.saveOpenInvoices(list);
      return list;
    }

    // Merge customer-scoped live results into the local cache without
    // wiping open invoices for other customers.
    final others = _dbService
        .getOpenInvoices()
        .where((i) => i.customerId != customerId)
        .toList();
    await _dbService.saveOpenInvoices([...others, ...list]);
    return list;
  }

  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) =>
      _dbService.updateCustomerGps(customerId, latitude, longitude);

  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) =>
      _dbService.updateCustomerContactFields(
        customerId,
        phone: phone,
        trn: trn,
      );

  @override
  List<StockTransfer> getLocalStockTransfers() =>
      _dbService.getLocalStockTransfers();

  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) =>
      _dbService.saveLocalStockTransfer(transfer);

  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchStockTransfers(
      startDate: startDate,
      endDate: endDate,
    );
    final transfers = raw.map((json) => StockTransferModel.fromJson(json)).toList();
    await _dbService.saveRemoteStockTransfers(transfers);
    return _dbService.getLocalStockTransfers();
  }

  @override
  Customer? getCustomerById(String id) => _dbService.getCustomerById(id);

  @override
  Organization? getOrganization() => _dbService.getOrganization();

  @override
  String? get assignedWarehouseId => _dbService.assignedWarehouseId;

  @override
  String? get primaryWarehouseId => _dbService.primaryWarehouseId;

  @override
  List<Warehouse> getWarehouses() => _dbService.getWarehouses();

  @override
  bool hasPendingCashClosingForToday() =>
      _dbService.hasPendingCashClosingForToday();

  @override
  Future<List<Item>> fetchRemoteItems({String? locationId}) async {
    final target = locationId ?? _dbService.assignedWarehouseId ?? '';
    final raw = await _apiClient.fetchItems(target);
    return raw.map((json) => ItemModel.fromJson(json)).toList();
  }

  @override
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    await _apiClient.updateCustomerGps(customerId, latitude, longitude);
  }

  @override
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    await _apiClient.updateCustomerContactFields(
      customerId,
      phone: phone,
      trn: trn,
    );
  }

  @override
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchCustomerStatement(
      customerId,
      startDate: startDate,
      endDate: endDate,
    );

    final rawWithName = Map<String, dynamic>.from(raw);
    if ((rawWithName['contact_name'] as String? ?? '').isEmpty ||
        rawWithName['contact_name'] == 'Demo Customer') {
      final customer = _dbService
          .getCustomers()
          .where((c) => c.id == customerId)
          .firstOrNull;
      if (customer != null) {
        rawWithName['contact_name'] = customer.name;
      }
    }

    return CustomerLedger.fromJson(rawWithName, customerId);
  }
}
