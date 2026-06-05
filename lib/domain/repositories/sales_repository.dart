import '../models/route.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/sales_invoice.dart';
import '../models/receipt_voucher.dart';
import '../models/sales_return.dart';
import '../models/expense_entry.dart';
import '../models/cash_closing.dart';
import '../models/open_invoice.dart';
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
  
  /// Retrieves list of inventory items currently stocked in the van.
  List<Item> getItems();

  /// Saves or refreshes item stocks locally.
  Future<void> saveItems(List<Item> items);
  
  /// Gets all sales invoices recorded locally.
  List<SalesInvoice> getLocalInvoices();

  /// Logs a new sales invoice locally and pushes it to local database cache.
  Future<void> saveLocalInvoice(SalesInvoice invoice);
  
  /// Gets all receipt vouchers collected locally.
  List<ReceiptVoucher> getLocalReceipts();

  /// Logs a new collection receipt locally and caches it.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher);
  
  /// Gets all sales returns logged locally.
  List<SalesReturn> getLocalReturns();

  /// Logs a credit note/sales return locally and caches it.
  Future<void> saveLocalReturn(SalesReturn salesReturn);
  
  /// Gets all route expenses filed locally.
  List<ExpenseEntry> getLocalExpenses();

  /// Saves a new multi-line expense entry locally.
  Future<void> saveLocalExpense(ExpenseEntry expense);
  
  /// Gets the daily cash closing reconciliation record, if filed.
  CashClosing? getLocalCashClosing();

  /// Saves/updates the end-of-trip daily cash closing.
  Future<void> saveLocalCashClosing(CashClosing closing);

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);

  /// Retrieves the current collection of pending synchronization items.
  List<SyncQueueItem> getSyncQueue();

  /// Retrieves open (unpaid) customer invoices.
  List<OpenInvoice> getOpenInvoices({String? customerId});
}

