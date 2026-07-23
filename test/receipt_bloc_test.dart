import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/features/receipts/bloc/receipt_bloc.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/data/services/sync_worker.dart';

class FakeSalesRepository implements SalesRepository {
  List<OpenInvoice> openInvoices = [];
  List<Customer> customers = [];
  List<ReceiptVoucher> receipts = [];
  List<SyncQueueItem> syncQueue = [];

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) {
    if (customerId != null) {
      return openInvoices.where((i) => i.customerId == customerId).toList();
    }
    return openInvoices;
  }

  int fetchRemoteOpenInvoicesCount = 0;
  bool throwOnFetchRemoteOpenInvoices = false;

  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async {
    fetchRemoteOpenInvoicesCount++;
    if (throwOnFetchRemoteOpenInvoices) throw Exception('offline');
    return getOpenInvoices(customerId: customerId);
  }

  @override
  List<Customer> getCustomers() => customers;

  @override
  List<ReceiptVoucher> getLocalReceipts() => receipts;

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    receipts.add(voucher);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    syncQueue.add(item);
  }

  @override
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    // No-op for tests
  }

  @override
  List<SyncQueueItem> getSyncQueue() => syncQueue;

  // Stub other methods
  @override
  List<RouteModel> getRoutes() => [];
  @override
  String? get activeRouteId => null;
  @override
  Future<void> setActiveRouteId(String? routeId) async {}
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
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
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
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
  List<MasterType> syncedMasters = [];
  bool throwOnSyncMaster = false;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    triggerCount++;
  }

  @override
  Future<void> clearFailedSyncItems() async {}

  @override
  Stream<String> get syncStatusStream => const Stream.empty();

  @override
  Stream<int> get syncCountStream => const Stream.empty();

  @override
  bool get isSyncing => false;

  @override
  List<SyncQueueItem> getSyncQueue() => [];

  @override
  Future<void> refreshMasterData() async {}

  @override
  Future<void> syncMaster(MasterType type) async {
    syncedMasters.add(type);
    if (throwOnSyncMaster) throw Exception('offline');
  }

  @override
  bool hasCoreMasters() => true;
}

void main() {
  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late ReceiptBloc bloc;

  final testCustomer = const Customer(
    id: 'cust_01',
    name: 'Customer A',
    companyName: 'Company A',
    email: '',
    phone: '',
    address: '',
    outstandingBalance: 1000,
    creditLimit: 999999,
    routeId: '',
    sequence: 1,
  );

  final invoice1 = OpenInvoice(
    invoiceId: 'inv_01',
    invoiceNumber: 'INV-101',
    customerId: 'cust_01',
    date: DateTime.now().subtract(const Duration(days: 10)),
    dueDate: DateTime.now().add(const Duration(days: 20)),
    total: 500,
    balance: 500,
    status: 'unpaid',
  );

  final invoice2 = OpenInvoice(
    invoiceId: 'inv_02',
    invoiceNumber: 'INV-102',
    customerId: 'cust_01',
    date: DateTime.now().subtract(const Duration(days: 5)),
    dueDate: DateTime.now().add(const Duration(days: 25)),
    total: 300,
    balance: 300,
    status: 'unpaid',
  );

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = ReceiptBloc(salesRepository: salesRepo, syncRepository: syncRepo);

    salesRepo.customers = [testCustomer];
    salesRepo.openInvoices = [invoice1, invoice2];
  });

  tearDown(() {
    bloc.close();
  });

  test('StartNewReceipt sets editing fields with empty allocations', () async {
    final future = bloc.stream.first;
    bloc.add(StartNewReceipt());
    await future;
    expect(bloc.state.editingAllocations, const []);
    expect(bloc.state.isEditingNew, true);
  });

  test('SetEditingReceiptCustomer triggers FIFO auto-allocation', () async {
    var future = bloc.stream.first;
    bloc.add(StartNewReceipt());
    await future;

    future = bloc.stream.first;
    bloc.add(const SetEditingAmount(600.0));
    await future;

    future = bloc.stream.first;
    bloc.add(SetEditingReceiptCustomer(testCustomer));
    await future;

    // After setting customer, it should allocate $600:
    // $500 to invoice1 (INV-101, oldest)
    // $100 to invoice2 (INV-102, newer)
    expect(bloc.state.editingAllocations.length, 2);

    final alloc1 = bloc.state.editingAllocations.firstWhere(
      (a) => a.invoiceId == 'inv_01',
    );
    final alloc2 = bloc.state.editingAllocations.firstWhere(
      (a) => a.invoiceId == 'inv_02',
    );

    expect(alloc1.amountApplied, 500.0);
    expect(alloc2.amountApplied, 100.0);
  });

  test('SetEditingReceiptCustomer fetches open invoices live from Zoho '
      'before allocating', () async {
    var future = bloc.stream.first;
    bloc.add(StartNewReceipt());
    await future;

    future = bloc.stream.first;
    bloc.add(SetEditingReceiptCustomer(testCustomer));
    await future;

    expect(salesRepo.fetchRemoteOpenInvoicesCount, 1);
  });

  test('SetEditingReceiptCustomer still allocates from the local cache when '
      'the live refresh fails (offline)', () async {
    salesRepo.throwOnFetchRemoteOpenInvoices = true;

    var future = bloc.stream.first;
    bloc.add(StartNewReceipt());
    await future;

    future = bloc.stream.first;
    bloc.add(const SetEditingAmount(600.0));
    await future;

    future = bloc.stream.first;
    bloc.add(SetEditingReceiptCustomer(testCustomer));
    await future;

    expect(bloc.state.editingAllocations.length, 2);
    expect(
      bloc.state.editingAllocations
          .firstWhere((a) => a.invoiceId == 'inv_01')
          .amountApplied,
      500.0,
    );
  });

  test('SetEditingAmount triggers FIFO auto-allocation', () async {
    var future = bloc.stream.first;
    bloc.add(StartNewReceipt());
    await future;

    future = bloc.stream.first;
    bloc.add(SetEditingReceiptCustomer(testCustomer));
    await future;

    future = bloc.stream.first;
    bloc.add(const SetEditingAmount(400.0));
    await future;

    // After setting amount, it should allocate $400:
    // $400 to invoice1 (INV-101, oldest)
    expect(bloc.state.editingAllocations.length, 1);

    final alloc1 = bloc.state.editingAllocations.firstWhere(
      (a) => a.invoiceId == 'inv_01',
    );
    expect(alloc1.amountApplied, 400.0);
  });

  test('UpdateReceiptAllocations overrides FIFO auto-allocation', () async {
    var future = bloc.stream.first;
    bloc.add(StartNewReceipt());
    await future;

    future = bloc.stream.first;
    bloc.add(SetEditingReceiptCustomer(testCustomer));
    await future;

    future = bloc.stream.first;
    bloc.add(const SetEditingAmount(400.0));
    await future;

    // Manual override allocation: $200 to inv_01, $200 to inv_02
    const overrides = [
      PaymentAllocation(
        invoiceId: 'inv_01',
        invoiceNumber: 'INV-101',
        amountApplied: 200.0,
      ),
      PaymentAllocation(
        invoiceId: 'inv_02',
        invoiceNumber: 'INV-102',
        amountApplied: 200.0,
      ),
    ];
    future = bloc.stream.first;
    bloc.add(const UpdateReceiptAllocations(overrides));
    await future;

    expect(bloc.state.editingAllocations, overrides);
  });
}
