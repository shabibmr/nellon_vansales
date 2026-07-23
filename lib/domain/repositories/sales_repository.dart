import '../models/route.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/sales_invoice.dart';
import '../models/receipt_voucher.dart';
import '../models/sales_return.dart';
import '../models/expense_entry.dart';
import '../models/cash_closing.dart';
import '../models/open_invoice.dart';
import '../models/sales_order.dart';
import '../models/stock_transfer.dart';
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

  /// Retrieves list of inventory items currently stocked in the van.
  List<Item> getItems();

  /// Saves or refreshes item stocks locally.
  Future<void> saveItems(List<Item> items);

  /// Resolves an item's multi-UOM conversions on demand.
  ///
  /// Returns the item unchanged if it already carries conversions or if they
  /// are cached locally; otherwise fetches `GET /items/{id}` from Zoho, caches
  /// the result (even when empty), and returns the enriched item. Falls back to
  /// the base-unit-only item when offline or the fetch fails.
  Future<Item> resolveItemUnitConversions(Item item);

  /// Gets all sales invoices recorded locally.
  List<SalesInvoice> getLocalInvoices();

  /// Logs a new sales invoice locally and pushes it to local database cache.
  Future<void> saveLocalInvoice(SalesInvoice invoice);

  /// Loads a single invoice by id: local cache first, then Zoho Books.
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId);

  /// Downloads invoices from Zoho Books, merges them into the local cache,
  /// and returns the resulting local list.
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Loads a single receipt/payment by id: local cache first, then Zoho Books.
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId);

  /// Loads a single sales return (credit note) by id: local cache first, then Zoho.
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId);

  /// Gets all sales orders recorded locally.
  List<SalesOrder> getLocalOrders();

  /// Logs a new sales order locally and caches it.
  Future<void> saveLocalOrder(SalesOrder order);

  /// Downloads sales orders from Zoho Books, merges them into the local cache,
  /// and returns the resulting local list. Omitting the date range pulls
  /// unfiltered (all salesperson history); passing one scopes the Zoho query.
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Reads a single sales order from Zoho Books by its permanent `zohoOrderId`.
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId);

  /// Gets all receipt vouchers collected locally.
  List<ReceiptVoucher> getLocalReceipts();

  /// Logs a new collection receipt locally and caches it.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher);

  /// Downloads receipts from Zoho Books, merges them into the local cache,
  /// and returns the resulting local list.
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Gets all sales returns logged locally.
  List<SalesReturn> getLocalReturns();

  /// Logs a credit note/sales return locally and caches it.
  Future<void> saveLocalReturn(SalesReturn salesReturn);

  /// Downloads sales returns from Zoho Books, merges them into the local
  /// cache, and returns the resulting local list.
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Gets all route expenses filed locally.
  List<ExpenseEntry> getLocalExpenses();

  /// Saves a new multi-line expense entry locally.
  Future<void> saveLocalExpense(ExpenseEntry expense);

  /// Downloads expenses from Zoho Books, merges them into the local cache,
  /// and returns the resulting local list.
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
}
