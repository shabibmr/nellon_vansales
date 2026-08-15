import '../models/route.dart';
import '../models/customer.dart';
import '../models/customer_ledger.dart';
import '../models/item.dart';
import '../models/organization.dart';
import '../models/sales_invoice.dart';
import '../models/receipt_voucher.dart';
import '../models/sales_return.dart';
import '../models/expense_entry.dart';
import '../models/cash_closing.dart';
import '../models/open_invoice.dart';
import '../models/sales_order.dart';
import '../models/stock_transfer.dart';
import '../models/warehouse.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract managing local van sales data access and session tracking.
///
/// Serves as the primary coordinator for local inventory queries, local transaction logging
/// (invoices, collections, returns, expenses, cash closing), route allocation, and sync-queue loading.
abstract class SalesRepository {
  /// Retrieves list of routes available for sales agents.
  List<RouteModel> getRoutes();

  /// Gets the currently selected active route ID.
  String? get activeRouteId;

  /// Selects and locks an active route for the delivery day.
  Future<void> setActiveRouteId(String? routeId);

  /// Retrieves the list of master customer entities synced to the van.
  List<Customer> getCustomers();

  /// Saves or refreshes customer entities in local cache.
  Future<void> saveCustomers(List<Customer> customers);

  /// Updates GPS coordinates for a single customer (by id) in local cache.
  /// Used for on-the-fly enrichment when capturing location for existing customers.
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude);

  /// Updates phone and/or TRN for a single customer in local cache.
  ///
  /// Also refreshes the contact-detail TRN cache so a later masters refresh
  /// does not wipe a user-entered tax number.
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  });

  /// Retrieves list of inventory items currently stocked in the van.
  List<Item> getItems();

  /// Saves or refreshes item stocks locally.
  Future<void> saveItems(List<Item> items);

  /// Resolves an item's multi-UOM conversions on demand.
  ///
  /// Returns the enriched [Item] plus [offlineFallback] = true when a network
  /// fetch was required but failed (no cache). Callers may show a snackbar in
  /// that case; the item is still usable in the base unit.
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(
    Item item,
  );

  /// Resolves TRN / billing address on demand (`GET /contacts/{id}`).
  ///
  /// The contacts list never includes `tax_reg_no`. First search tap fetches
  /// and caches the detail (even when TRN is empty). Thermal print reads Hive
  /// only. [offlineFallback] is true when a required fetch failed.
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  );

  /// Gets all sales invoices recorded locally.
  List<SalesInvoice> getLocalInvoices();

  /// Logs a new sales invoice locally and pushes it to local database cache.
  Future<void> saveLocalInvoice(SalesInvoice invoice);

  /// Loads a single invoice by id.
  ///
  /// By default uses local cache first, then Zoho. When [forceRemote] is true,
  /// prefers Zoho (and updates the local cache on success).
  ///
  /// [allowOfflineFallback] (default true): if the remote call fails or returns
  /// empty and a local copy exists, return the local copy. Explicit refresh
  /// should pass `false` so network failures surface to the user.
  Future<SalesInvoice?> fetchInvoiceById(
    String invoiceId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Downloads invoice **headers** from Zoho Books (list endpoint only — no
  /// per-invoice detail), merges them into the local cache, and returns the
  /// resulting local list. Line items load via [fetchInvoiceById] on open.
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Loads a single receipt/payment by id.
  ///
  /// See [fetchInvoiceById] for [forceRemote] / [allowOfflineFallback] semantics.
  Future<ReceiptVoucher?> fetchReceiptById(
    String paymentId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Loads a single sales return (credit note) by id.
  ///
  /// See [fetchInvoiceById] for [forceRemote] / [allowOfflineFallback] semantics.
  Future<SalesReturn?> fetchSalesReturnById(
    String creditNoteId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Loads a single expense by id.
  ///
  /// See [fetchInvoiceById] for [forceRemote] / [allowOfflineFallback] semantics.
  Future<ExpenseEntry?> fetchExpenseById(
    String expenseId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Gets all sales orders recorded locally.
  List<SalesOrder> getLocalOrders();

  /// Logs a new sales order locally and caches it.
  Future<void> saveLocalOrder(SalesOrder order);

  /// Enqueues a create (`sales_order`) or update (`update_sales_order`) sync
  /// item for [order]. Call after [saveLocalOrder]. Mapping to the queue
  /// payload lives in the data layer so UI/BLoCs stay on domain types.
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate});

  /// Downloads sales order **headers** from Zoho Books (list endpoint only —
  /// no per-order detail), merges them into the local cache, and returns the
  /// resulting local list. Line items load via [fetchRemoteOrder] on open.
  /// Omitting the date range pulls unfiltered history; passing one scopes Zoho.
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Reads a single sales order from Zoho Books by its permanent `zohoOrderId`.
  ///
  /// When [allowOfflineFallback] is true and the remote call fails, returns the
  /// matching local order if present.
  Future<SalesOrder?> fetchRemoteOrder(
    String zohoOrderId, {
    bool allowOfflineFallback = false,
  });

  /// Gets all receipt vouchers collected locally.
  List<ReceiptVoucher> getLocalReceipts();

  /// Logs a new collection receipt locally and caches it.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher);

  /// Downloads receipt **headers** from Zoho Books, merges them into the local
  /// cache, and returns the resulting local list. Invoice allocations load via
  /// [fetchReceiptById] when the editor opens.
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Gets all sales returns logged locally.
  List<SalesReturn> getLocalReturns();

  /// Logs a credit note/sales return locally and caches it.
  Future<void> saveLocalReturn(SalesReturn salesReturn);

  /// Downloads sales return **headers** from Zoho Books (list endpoint only —
  /// no per-return detail), merges them into the local cache, and returns the
  /// resulting local list. Line items load via [fetchSalesReturnById] on open.
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Gets all route expenses filed locally.
  List<ExpenseEntry> getLocalExpenses();

  /// Saves a new multi-line expense entry locally.
  Future<void> saveLocalExpense(ExpenseEntry expense);

  /// Downloads expense **headers** from Zoho Books (list endpoint only — no
  /// per-expense detail), merges them into the local cache, and returns the
  /// resulting local list. Lines load via [fetchExpenseById] on open.
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Gets the daily cash closing reconciliation record, if filed.
  CashClosing? getLocalCashClosing();

  /// Saves/updates the end-of-trip daily cash closing.
  Future<void> saveLocalCashClosing(CashClosing closing);

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);

  /// Retrieves the current collection of pending synchronization items.
  List<SyncQueueItem> getSyncQueue();

  /// Retrieves open (unpaid) customer invoices from the local cache, if any.
  /// Prefer [fetchRemoteOpenInvoices] for live balances when online.
  List<OpenInvoice> getOpenInvoices({String? customerId});

  /// Fetches open (unpaid) invoices live from Zoho Books.
  ///
  /// When [customerId] is set, scopes the request to that customer. Results are
  /// also written into the local open-invoice cache so offline UI can fall back
  /// to the last successful live fetch.
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId});

  /// Gets all stock transfers (Issue to Van / Stock Unloading) recorded locally.
  List<StockTransfer> getLocalStockTransfers();

  /// Logs a new stock transfer locally, caches it, and adjusts van stock levels.
  Future<void> saveLocalStockTransfer(StockTransfer transfer);

  /// Downloads stock transfers from Zoho, merges them into the local cache,
  /// and returns the resulting local list.
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Fetches full ledger statement for a customer over an optional date range.
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Indexed customer lookup (local cache).
  Customer? getCustomerById(String id);

  /// Cached organization details for PDF / currency context.
  Organization? getOrganization();

  /// Van / session warehouse id assigned to the active salesperson.
  String? get assignedWarehouseId;

  /// Organization primary warehouse id (e.g. main store).
  String? get primaryWarehouseId;

  /// Cached warehouse master list.
  List<Warehouse> getWarehouses();

  /// True when today's sales activity still needs cash closing.
  bool hasPendingCashClosingForToday();

  /// Live item stock from Zoho for [locationId] (defaults to assigned warehouse).
  Future<List<Item>> fetchRemoteItems({String? locationId});

  /// Best-effort remote GPS push for an existing Zoho contact. Throws on failure
  /// so callers can fall back to the offline queue.
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  );

  /// Best-effort remote phone / TRN push for an existing Zoho contact.
  /// Throws on failure so callers can fall back to the offline queue.
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  });
}
