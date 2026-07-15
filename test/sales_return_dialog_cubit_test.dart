import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/ui/features/dashboard/cubit/sales_return_dialog_cubit.dart';

class FakeSalesRepository implements SalesRepository {
  List<SalesInvoice> invoices = [];
  List<Item> items = [];
  List<SalesReturn> savedReturns = [];
  List<SyncQueueItem> queue = [];
  bool shouldThrowOnSave = false;
  int saveCallCount = 0;

  @override
  List<SalesInvoice> getLocalInvoices() => invoices;

  @override
  List<Item> getItems() => items;

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    saveCallCount++;
    if (shouldThrowOnSave) throw Exception('Save failed');
    savedReturns.add(salesReturn);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {}

  @override
  List<Customer> getCustomers() => [];

  @override
  Future<void> saveCustomers(List<Customer> customers) async {}

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
  List<RouteModel> getRoutes() => [];

  @override
  String? get activeRouteId => null;

  @override
  Future<void> setActiveRouteId(String? routeId) async {}

  @override
  Future<void> saveItems(List<Item> items) async {}

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}

  @override
  List<SalesOrder> getLocalOrders() => [];

  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}

  @override
  Future<List<SalesOrder>> fetchRemoteOrders() async => [];

  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;

  @override
  List<SalesReturn> getLocalReturns() => savedReturns;

  @override
  List<ExpenseEntry> getLocalExpenses() => [];

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {}

  @override
  CashClosing? getLocalCashClosing() => null;

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}

  @override
  List<StockTransfer> getLocalStockTransfers() => [];

  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
}

class FakeHiveDatabaseService extends HiveDatabaseService {
  @override
  String? get assignedWarehouseId => 'van_wh_01';

  @override
  String? get activeRouteId => null;
}

class FakeSyncWorker extends SyncWorker {
  FakeSyncWorker() : super(dbService: FakeHiveDatabaseService(), apiClient: FakeZohoApiClient());

  int syncPendingCount = 0;

  @override
  Future<void> syncPendingItems({bool forceRetryAll = false}) async {
    syncPendingCount++;
  }
}

class FakeZohoApiClient extends ZohoApiClient {
  FakeZohoApiClient() : super(dbService: FakeHiveDatabaseService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const customer = Customer(
    id: 'cust_1',
    name: 'Customer 1',
    companyName: 'Shop 1',
    email: '',
    phone: '',
    address: '',
    outstandingBalance: 0,
    creditLimit: 0,
    routeId: 'route_1',
    sequence: 1,
  );

  const milk = Item(
    id: 'item_milk',
    name: 'Milk',
    sku: 'MLK-001',
    rate: 10,
    stock: 50,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );

  const bread = Item(
    id: 'item_bread',
    name: 'Bread',
    sku: 'BRD-001',
    rate: 5,
    stock: 20,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );

  final invoice = SalesInvoice(
    id: 'inv_1',
    invoiceNumber: 'INV-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 2, 1),
    dueDate: DateTime(2026, 2, 15),
    items: const [
      InvoiceLineItem(
        item: milk,
        quantity: 4,
        rate: 10,
        taxPercentage: 0,
      ),
    ],
    notes: '',
  );

  late FakeSalesRepository repo;
  late FakeSyncWorker syncWorker;
  late SalesReturnDialogCubit cubit;

  setUp(() {
    repo = FakeSalesRepository()
      ..invoices = [invoice]
      ..items = [milk, bread];
    syncWorker = FakeSyncWorker();
    cubit = SalesReturnDialogCubit(
      customer: customer,
      salesRepository: repo,
      syncWorker: syncWorker,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  test('loadEligibleItems filters to purchased items only', () {
    cubit.loadEligibleItems();

    expect(cubit.state.eligibleItems.length, 1);
    expect(cubit.state.eligibleItems.first.id, 'item_milk');
    expect(cubit.state.hasNoPurchaseHistory, isFalse);
  });

  test('loadEligibleItems with no history sets hasNoPurchaseHistory', () {
    repo.invoices = [];
    cubit.loadEligibleItems();

    expect(cubit.state.hasNoPurchaseHistory, isTrue);
  });

  test('selectItem builds matching invoices and clears quantities', () {
    cubit.loadEligibleItems();
    cubit.selectItem(milk);

    expect(cubit.state.selectedItem, milk);
    expect(cubit.state.matchingInvoices.length, 1);
    expect(cubit.state.matchingInvoices.first.id, 'inv_1');
    expect(cubit.state.quantities, isEmpty);
  });

  test('setQuantity enables canSubmit only when total qty > 0', () {
    cubit.loadEligibleItems();
    cubit.selectItem(milk);

    expect(cubit.state.canSubmit, isFalse);

    cubit.setQuantity('inv_1', 2);

    expect(cubit.state.canSubmit, isTrue);
    expect(cubit.state.quantities['inv_1'], 2);
  });

  test('submit with zero qty does not call repository', () async {
    cubit.loadEligibleItems();
    cubit.selectItem(milk);

    await cubit.submit();

    expect(repo.saveCallCount, 0);
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.success, isFalse);
  });

  test('submit success saves return, enqueues sync, and emits success', () async {
    cubit.loadEligibleItems();
    cubit.selectItem(milk);
    cubit.setQuantity('inv_1', 2);

    await cubit.submit();

    expect(repo.saveCallCount, 1);
    expect(repo.savedReturns.length, 1);
    expect(repo.savedReturns.first.items.length, 1);
    expect(repo.savedReturns.first.items.first.returnedQuantity, 2);
    expect(repo.savedReturns.first.reason, 'Damaged packaging');
    expect(
      repo.savedReturns.first.creditNoteNumber.startsWith('RET-TEMP-'),
      isTrue,
    );
    expect(repo.queue.length, 1);
    expect(repo.queue.first.type, 'return');
    expect(syncWorker.syncPendingCount, 1);
    expect(cubit.state.success, isTrue);
    expect(cubit.state.submitting, isFalse);
  });

  test('submit while already submitting only saves once', () async {
    cubit.loadEligibleItems();
    cubit.selectItem(milk);
    cubit.setQuantity('inv_1', 1);

    final first = cubit.submit();
    await cubit.submit();
    await first;

    expect(repo.saveCallCount, 1);
  });

  test('submit failure clears submitting and sets errorMessage', () async {
    repo.shouldThrowOnSave = true;
    cubit.loadEligibleItems();
    cubit.selectItem(milk);
    cubit.setQuantity('inv_1', 1);

    await cubit.submit();

    expect(cubit.state.submitting, isFalse);
    expect(cubit.state.errorMessage, contains('Save failed'));
    expect(cubit.state.success, isFalse);
  });

  test('selectItem emits fresh quantity map instances', () {
    cubit.loadEligibleItems();
    cubit.selectItem(milk);
    cubit.setQuantity('inv_1', 2);
    final firstMap = cubit.state.quantities;

    cubit.selectItem(milk);
    final secondMap = cubit.state.quantities;

    expect(identical(firstMap, secondMap), isFalse);
    expect(secondMap, isEmpty);
  });
}