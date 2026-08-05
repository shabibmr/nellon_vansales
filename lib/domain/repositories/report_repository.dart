import '../models/customer.dart';
import '../models/expense_entry.dart';
import '../models/item.dart';
import '../models/open_invoice.dart';
import '../models/receipt_voucher.dart';
import '../models/sales_invoice.dart';
import '../models/sales_order.dart';
import '../models/sales_return.dart';
import '../models/stock_transfer.dart';

/// Abstract contract for fetching remote and aggregated report datasets.
///
/// Encapsulates JSON parsing and local session scoping (e.g. location filtering)
/// away from UI view files.
abstract class ReportRepository {
  /// Fetches sales invoices for reporting, scoped to the current salesperson location if configured.
  Future<List<SalesInvoice>> fetchInvoices();

  /// Fetches sales orders for reporting.
  Future<List<SalesOrder>> fetchSalesOrders();

  /// Fetches customer payment receipts for reporting.
  Future<List<ReceiptVoucher>> fetchReceipts();

  /// Fetches logged expense entries for reporting.
  Future<List<ExpenseEntry>> fetchExpenses();

  /// Fetches sales returns (credit notes) for reporting.
  Future<List<SalesReturn>> fetchSalesReturns();

  /// Fetches open (unpaid) customer invoices for reporting.
  Future<List<OpenInvoice>> fetchOpenInvoices();

  /// Fetches customer master records for reporting.
  Future<List<Customer>> fetchCustomers();

  /// Fetches inventory item master records and van stock levels for reporting.
  Future<List<Item>> fetchItems({String? locationId});

  /// Fetches stock transfers (Issue to Van / Stock Unloading) for reporting.
  Future<List<StockTransfer>> fetchStockTransfers();
}
