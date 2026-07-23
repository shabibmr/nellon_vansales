import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/ui/features/dashboard/cubit/create_customer_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/create_customer_state.dart';

class FakeSalesRepository implements SalesRepository {
  List<Customer> customers = [];
  List<SyncQueueItem> queue = [];
  bool shouldThrow = false;

  @override
  List<Customer> getCustomers() => customers;

  @override
  Future<void> saveCustomers(List<Customer> customers) async {
    if (shouldThrow) throw Exception('Database error');
    this.customers = customers;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  // Stub other methods
  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => queue;
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async =>
      [];
  @override
  List<ReceiptVoucher> getLocalReceipts() => [];
  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  List<RouteModel> getRoutes() => [];
  @override
  String? get activeRouteId => null;
  @override
  Future<void> setActiveRouteId(String? routeId) async {}
  @override
  List<Item> getItems() => [];
  @override
  Future<void> saveItems(List<Item> items) async {}

  @override
  Future<Item> resolveItemUnitConversions(Item item) async => item;
  @override
  List<SalesInvoice> getLocalInvoices() => [];
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId) async => null;
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId) async => null;
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;
  @override
  List<SalesReturn> getLocalReturns() => [];
  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}
  @override
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  List<ExpenseEntry> getLocalExpenses() => [];
  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {}
  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  CashClosing? getLocalCashClosing() => null;
  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}
  @override
  List<StockTransfer> getLocalStockTransfers() => [];
  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
}

void main() {
  late FakeSalesRepository salesRepo;
  late CreateCustomerCubit cubit;

  setUp(() {
    salesRepo = FakeSalesRepository();
    cubit = CreateCustomerCubit(salesRepository: salesRepo);
  });

  tearDown(() {
    cubit.close();
  });

  test('Initial state is CreateCustomerInitial', () {
    expect(cubit.state, CreateCustomerInitial());
  });

  test('submit successfully saves customer locally and queues Zoho sync item', () async {
    final future = cubit.stream.firstWhere((state) => state is CreateCustomerSuccess);

    await cubit.submit(
      name: 'John Doe',
      company: 'John Shop',
      email: 'john@example.com',
      phone: '1234567890',
      address: '123 St',
      creditLimit: 1500.0,
      activeRouteId: 'route_123',
      latitude: 12.34,
      longitude: 56.78,
    );

    final state = await future as CreateCustomerSuccess;
    expect(state.customer.name, 'John Doe');
    expect(state.customer.companyName, 'John Shop');
    expect(state.customer.routeId, 'route_123');
    expect(state.customer.latitude, 12.34);
    expect(state.customer.longitude, 56.78);
    expect(state.customer.isPendingSync, true);

    // Verify local storage
    expect(salesRepo.customers.length, 1);
    expect(salesRepo.customers.first.name, 'John Doe');

    // Verify sync queue payload
    expect(salesRepo.queue.length, 1);
    final syncItem = salesRepo.queue.first;
    expect(syncItem.type, 'customer');
    expect(syncItem.payload['contact_name'], 'John Doe');
    expect(syncItem.payload['credit_limit'], 1500.0);
    final customFields = syncItem.payload['custom_fields'] as List;
    expect(customFields[0]['api_name'], 'cf_latitude');
    expect(customFields[0]['value'], '12.34');
  });

  test('submit failure path emits CreateCustomerFailure state', () async {
    salesRepo.shouldThrow = true;
    final future = cubit.stream.firstWhere((state) => state is CreateCustomerFailure);

    await cubit.submit(
      name: 'John Doe',
      company: 'John Shop',
      email: 'john@example.com',
      phone: '1234567890',
      address: '123 St',
      creditLimit: 1500.0,
      activeRouteId: 'route_123',
    );

    final state = await future as CreateCustomerFailure;
    expect(state.message, contains('Database error'));
    expect(salesRepo.queue.isEmpty, true);
  });
}
