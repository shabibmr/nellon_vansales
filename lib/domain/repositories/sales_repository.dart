import '../models/route.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/sales_invoice.dart';
import '../models/receipt_voucher.dart';
import '../models/sales_return.dart';
import '../models/expense_entry.dart';
import '../models/cash_closing.dart';
import '../../data/models/sync_queue_item.dart';

abstract class SalesRepository {
  List<RouteModel> getRoutes();
  String? get activeRouteId;
  Future<void> setActiveRouteId(String? routeId);
  
  List<Customer> getCustomers();
  Future<void> saveCustomers(List<Customer> customers);
  
  List<Item> getItems();
  Future<void> saveItems(List<Item> items);
  
  List<SalesInvoice> getLocalInvoices();
  Future<void> saveLocalInvoice(SalesInvoice invoice);
  
  List<ReceiptVoucher> getLocalReceipts();
  Future<void> saveLocalReceipt(ReceiptVoucher voucher);
  
  List<SalesReturn> getLocalReturns();
  Future<void> saveLocalReturn(SalesReturn salesReturn);
  
  List<ExpenseEntry> getLocalExpenses();
  Future<void> saveLocalExpense(ExpenseEntry expense);
  
  CashClosing? getLocalCashClosing();
  Future<void> saveLocalCashClosing(CashClosing closing);

  Future<void> enqueueSyncItem(SyncQueueItem item);
  List<SyncQueueItem> getSyncQueue();
}
