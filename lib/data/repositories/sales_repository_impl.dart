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
import '../../domain/repositories/sales_repository.dart';
import '../models/sync_queue_item.dart';
import '../models/sales_order_model.dart';
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
  List<SalesInvoice> getLocalInvoices() => _dbService.getLocalInvoices();

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) =>
      _dbService.saveLocalInvoice(invoice);

  @override
  List<SalesOrder> getLocalOrders() => _dbService.getLocalOrders();

  @override
  Future<void> saveLocalOrder(SalesOrder order) =>
      _dbService.saveLocalOrder(order);

  @override
  Future<List<SalesOrder>> fetchRemoteOrders() async {
    final raw = await _apiClient.fetchSalesOrders();
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
  List<ReceiptVoucher> getLocalReceipts() => _dbService.getLocalReceipts();

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) =>
      _dbService.saveLocalReceipt(voucher);

  @override
  List<SalesReturn> getLocalReturns() => _dbService.getLocalReturns();

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) =>
      _dbService.saveLocalReturn(salesReturn);

  @override
  List<ExpenseEntry> getLocalExpenses() => _dbService.getLocalExpenses();

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) =>
      _dbService.saveLocalExpense(expense);

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
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) =>
      _dbService.updateCustomerGps(customerId, latitude, longitude);
}
