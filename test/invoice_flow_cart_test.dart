import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
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
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_bloc.dart';

class FakeSalesRepository implements SalesRepository {
  final List<SalesInvoice> invoices = [];
  final List<SyncQueueItem> queue = [];
  bool throwOnSave = false;

  @override
  List<SalesInvoice> getLocalInvoices() => List.from(invoices);

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    if (throwOnSave) throw Exception('save failed');
    invoices.add(invoice);
  }

  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId) async {
    try {
      return invoices.firstWhere((i) => i.id == invoiceId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId) async => null;

  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId) async => null;

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

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
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {}
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

class FakeSyncRepository implements SyncRepository {
  int triggerCount = 0;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    triggerCount++;
  }

  @override
  Stream<String> get syncStatusStream => const Stream.empty();
  @override
  Stream<int> get syncCountStream => const Stream.empty();
  @override
  bool get isSyncing => false;
  @override
  List<SyncQueueItem> getSyncQueue() => [];
  @override
  Future<void> clearFailedSyncItems() async {}
  @override
  Future<void> refreshMasterData() async {}
  @override
  Future<void> syncMaster(MasterType type) async {}
  @override
  bool hasCoreMasters() => true;
}

Item _item({
  required String id,
  required String name,
  double stock = 5,
  double rate = 10,
}) {
  return Item(
    id: id,
    name: name,
    sku: 'SKU-$id',
    rate: rate,
    stock: stock,
    description: '',
    taxName: 'VAT',
    taxPercentage: 5,
  );
}

Customer get _customer => const Customer(
      id: 'c1',
      name: 'Acme',
      companyName: 'Acme Co',
      email: 'a@b.com',
      phone: '1',
      address: 'x',
      outstandingBalance: 0,
      creditLimit: 1000,
      routeId: 'r1',
      sequence: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late SalesInvoiceBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = SalesInvoiceBloc(
      salesRepository: salesRepo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('ClearCart empties editingItems so sheet opens clean', () async {
    final item = _item(id: 'i1', name: 'Widget');
    bloc.add(AddToCart(item, 2));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    bloc.add(ClearCart());
    final cleared = await bloc.stream.firstWhere((s) => s.editingItems.isEmpty);
    expect(cleared.editingItems, isEmpty);
    expect(cleared.cart, isEmpty);
  });

  test('AddToCart over stock emits error and leaves cart unchanged', () async {
    final item = _item(id: 'i1', name: 'Widget', stock: 1);
    bloc.add(AddToCart(item, 1));
    await bloc.stream.firstWhere((s) => s.editingItems.length == 1);

    bloc.add(AddToCart(item, 1));
    final rejected = await bloc.stream.firstWhere((s) => s.errorMessage != null);

    expect(rejected.errorMessage, contains('only 1 available'));
    expect(rejected.editingItems.single.quantity, 1);
  });

  test('UpdateCartQuantity over stock emits error without changing qty', () async {
    final item = _item(id: 'i1', name: 'Widget', stock: 2);
    bloc.add(AddToCart(item, 1));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    bloc.add(UpdateCartQuantity(item, 5));
    final rejected = await bloc.stream.firstWhere((s) => s.errorMessage != null);

    expect(rejected.errorMessage, isNotNull);
    expect(rejected.editingItems.single.quantity, 1);
  });

  test('CheckoutRequested success clears cart and sets successMessage', () async {
    final item = _item(id: 'i1', name: 'Widget', stock: 3);
    bloc.add(AddToCart(item, 2));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    bloc.add(CheckoutRequested(customer: _customer, notes: 'Van Sales Checkout'));
    final done = await bloc.stream.firstWhere(
      (s) => s.successMessage != null && !s.isLoading,
    );

    expect(done.editingItems, isEmpty);
    expect(done.successMessage, contains('queued offline'));
    expect(salesRepo.invoices, hasLength(1));
    expect(salesRepo.queue, hasLength(1));
    expect(syncRepo.triggerCount, 1);
  });

  test('CheckoutRequested failure keeps cart and sets errorMessage', () async {
    salesRepo.throwOnSave = true;
    final item = _item(id: 'i1', name: 'Widget', stock: 3);
    bloc.add(AddToCart(item, 1));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    bloc.add(CheckoutRequested(customer: _customer, notes: 'x'));
    final failed = await bloc.stream.firstWhere(
      (s) => s.errorMessage != null && !s.isLoading,
    );

    expect(failed.editingItems, isNotEmpty);
    expect(failed.errorMessage, contains('save failed'));
    expect(failed.successMessage, isNull);
  });

  test('CheckoutRequested is guarded against double-submit while loading', () async {
    final item = _item(id: 'i1', name: 'Widget', stock: 3);
    bloc.add(AddToCart(item, 1));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    // First checkout will await save; second should no-op while isLoading.
    bloc.add(CheckoutRequested(customer: _customer, notes: 'a'));
    bloc.add(CheckoutRequested(customer: _customer, notes: 'b'));

    final done = await bloc.stream.firstWhere(
      (s) => s.successMessage != null && !s.isLoading,
    );

    expect(salesRepo.invoices, hasLength(1));
    expect(done.editingItems, isEmpty);
  });

  test('ClearMessages clears sticky error and success', () async {
    final item = _item(id: 'i1', name: 'Widget', stock: 0);
    bloc.add(AddToCart(item, 1));
    await bloc.stream.firstWhere((s) => s.errorMessage != null);

    bloc.add(ClearMessages());
    final cleared = await bloc.stream.firstWhere((s) => s.errorMessage == null);
    expect(cleared.errorMessage, isNull);
    expect(cleared.successMessage, isNull);
  });
}
