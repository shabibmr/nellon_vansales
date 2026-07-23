import '../../domain/models/route.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/item.dart';
import '../../domain/models/sales_invoice.dart';
import '../../domain/models/receipt_voucher.dart';
import '../../domain/models/sales_return.dart';
import '../../domain/models/expense_entry.dart';
import '../../domain/models/cash_closing.dart';
import '../../domain/models/open_invoice.dart';
import '../../domain/models/sales_order.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/models/unit_conversion.dart';
import '../../domain/repositories/sales_repository.dart';
import '../models/sync_queue_item.dart';
import '../models/unit_conversion_model.dart';
import '../services/app_logger.dart';
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
  Future<Item> resolveItemUnitConversions(Item item) async {
    // Already enriched (e.g. carried on an existing line item) — nothing to do.
    if (item.unitConversions.isNotEmpty) return item;

    // Previously resolved: serve from the dedicated item-UOM box. A cached but
    // empty entry means "checked, none exist" — still short-circuits the fetch.
    if (_dbService.hasItemUnitConversions(item.id)) {
      final cached = _dbService.getItemUnitConversions(item.id);
      return cached.isEmpty ? item : item.copyWith(unitConversions: cached);
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
      return conversions.isEmpty
          ? item
          : item.copyWith(unitConversions: conversions);
    } catch (e) {
      // Offline / rate-limited / any failure: fall back to base-unit-only and
      // do NOT cache, so a later online selection retries the fetch.
      AppLogger.error(
        'SalesRepository',
        'resolveItemUnitConversions(${item.id}) error: $e',
      );
      return item;
    }
  }

  @override
  List<SalesInvoice> getLocalInvoices() => _dbService.getLocalInvoices();

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) =>
      _dbService.saveLocalInvoice(invoice);

  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId) async {
    if (invoiceId.isEmpty) return null;
    for (final inv in _dbService.getLocalInvoices()) {
      if (inv.id == invoiceId) return inv;
    }
    final json = await _apiClient.fetchInvoiceDetail(invoiceId);
    if (json.isEmpty) return null;
    return SalesInvoiceModel.fromJson(json);
  }

  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchInvoices(
      startDate: startDate,
      endDate: endDate,
    );
    final invoices = raw.map((json) => SalesInvoiceModel.fromJson(json)).toList();
    await _dbService.saveRemoteInvoices(invoices);
    return _dbService.getLocalInvoices();
  }

  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId) async {
    if (paymentId.isEmpty) return null;
    for (final rec in _dbService.getLocalReceipts()) {
      if (rec.id == paymentId) return rec;
    }
    final json = await _apiClient.fetchReceiptDetail(paymentId);
    if (json.isEmpty) return null;
    return ReceiptVoucherModel.fromJson(json);
  }

  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId) async {
    if (creditNoteId.isEmpty) return null;
    for (final ret in _dbService.getLocalReturns()) {
      if (ret.id == creditNoteId) return ret;
    }
    final json = await _apiClient.fetchSalesReturnDetail(creditNoteId);
    if (json.isEmpty) return null;
    return SalesReturnModel.fromJson(json);
  }

  @override
  List<SalesOrder> getLocalOrders() => _dbService.getLocalOrders();

  @override
  Future<void> saveLocalOrder(SalesOrder order) =>
      _dbService.saveLocalOrder(order);

  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final raw = await _apiClient.fetchSalesOrders(
      startDate: startDate,
      endDate: endDate,
    );
    final orders = raw.map((json) => SalesOrderModel.fromJson(json)).toList();
    await _dbService.saveRemoteOrders(orders);
    return _dbService.getLocalOrders();
  }

  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async {
    final json = await _apiClient.fetchSalesOrder(zohoOrderId);
    if (json.isEmpty) return null;
    return SalesOrderModel.fromJson(json);
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
    final receipts = raw.map((json) => ReceiptVoucherModel.fromJson(json)).toList();
    await _dbService.saveRemoteReceipts(receipts);
    // API is already series-scoped; re-apply client-side so a polluted local
    // cache (pre-filter downloads) cannot surface other salesmen's receipts.
    return getLocalReceipts();
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
    final raw = await _apiClient.fetchSalesReturns(
      startDate: startDate,
      endDate: endDate,
    );
    final returns = raw.map((json) => SalesReturnModel.fromJson(json)).toList();
    await _dbService.saveRemoteReturns(returns);
    return _dbService.getLocalReturns();
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
    final raw = await _apiClient.fetchExpenses(
      startDate: startDate,
      endDate: endDate,
    );
    final remote =
        raw.map((json) => ExpenseEntryModel.fromJson(json)).toList();
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
}
