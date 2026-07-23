import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
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
import 'package:van_sales/ui/features/dashboard/bloc/receipt_allocation_bloc.dart';
import 'package:van_sales/ui/features/dashboard/bloc/receipt_allocation_event.dart';

class FakeSalesRepository implements SalesRepository {
  List<OpenInvoice> openInvoices = [];
  List<ReceiptVoucher> receipts = [];
  List<SyncQueueItem> queue = [];

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => openInvoices;

  int fetchRemoteOpenInvoicesCount = 0;
  bool throwOnFetchRemoteOpenInvoices = false;

  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async {
    fetchRemoteOpenInvoicesCount++;
    if (throwOnFetchRemoteOpenInvoices) throw Exception('offline');
    return openInvoices;
  }

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    receipts.add(voucher);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  // Stub other methods
  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => queue;
  @override
  List<ReceiptVoucher> getLocalReceipts() => receipts;
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {}
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

class FakeHiveDatabaseService extends HiveDatabaseService {
  @override
  String? get assignedWarehouseId => 'van_wh_01';
  @override
  String? get activeRouteId => null;
}

class FakeSyncWorker extends SyncWorker {
  FakeSyncWorker() : super(dbService: FakeHiveDatabaseService(), apiClient: FakeZohoApiClient());

  int syncMasterCount = 0;
  MasterType? lastSyncedMaster;

  @override
  Future<void> syncMaster(MasterType type) async {
    syncMasterCount++;
    lastSyncedMaster = type;
  }

  @override
  Future<void> syncPendingItems({bool forceRetryAll = false}) async {}
}

class FakeZohoApiClient extends ZohoApiClient {
  FakeZohoApiClient() : super(dbService: FakeHiveDatabaseService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSalesRepository salesRepo;
  late FakeSyncWorker syncWorker;
  late ReceiptAllocationBloc bloc;

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

  final invoiceOld = OpenInvoice(
    invoiceId: 'inv_old',
    invoiceNumber: 'INV-101',
    customerId: 'cust_01',
    date: DateTime.now().subtract(const Duration(days: 10)),
    dueDate: DateTime.now().add(const Duration(days: 20)),
    total: 500,
    balance: 500,
    status: 'unpaid',
  );

  final invoiceNew = OpenInvoice(
    invoiceId: 'inv_new',
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
    salesRepo.openInvoices = [invoiceOld, invoiceNew];
    syncWorker = FakeSyncWorker();
    bloc = ReceiptAllocationBloc(salesRepository: salesRepo, syncWorker: syncWorker);
  });

  tearDown(() {
    bloc.close();
  });

  test('ReceiptAllocationStarted loads cached open invoices and fetches live from Zoho', () async {
    final stateFuture = bloc.stream.first;
    bloc.add(ReceiptAllocationStarted(testCustomer));

    final state = await stateFuture;
    expect(state.customer, testCustomer);
    expect(state.openInvoices.length, 2);
    expect(state.openInvoices.first, invoiceOld); // Oldest first
    expect(state.isLoading, true);

    // Wait for the async live refresh to complete
    await bloc.stream.firstWhere((s) => !s.isLoading);
    expect(salesRepo.fetchRemoteOpenInvoicesCount, 1);
  });

  test('PaymentAmountChanged auto-allocates using oldest-first FIFO and resets manual override', () async {
    final startFuture = bloc.stream.firstWhere((s) => !s.isLoading);
    bloc.add(ReceiptAllocationStarted(testCustomer));
    await startFuture;

    final changeFuture = bloc.stream.first;
    bloc.add(const PaymentAmountChanged('600.00'));
    final state = await changeFuture;

    expect(state.allocations.length, 2);
    expect(state.allocations.first.invoiceId, 'inv_old');
    expect(state.allocations.first.amountApplied, 500.0);
    expect(state.allocations.last.invoiceId, 'inv_new');
    expect(state.allocations.last.amountApplied, 100.0);
    expect(state.hasManualOverride, false);
    expect(state.canSubmit, true);
  });

  test('InvoiceAllocationEdited mutates single invoice allocation and sets manual override', () async {
    final startFuture = bloc.stream.firstWhere((s) => !s.isLoading);
    bloc.add(ReceiptAllocationStarted(testCustomer));
    await startFuture;

    // Set initial amount to 600.0 (FIFO would allocate 500 & 100)
    final changeFuture = bloc.stream.first;
    bloc.add(const PaymentAmountChanged('600.00'));
    await changeFuture;

    // Edit old invoice allocation to 400.0 (total allocated = 500, which is <= 600)
    final editFuture = bloc.stream.first;
    bloc.add(const InvoiceAllocationEdited(
      invoiceId: 'inv_old',
      invoiceNumber: 'INV-101',
      value: '400.00',
    ));
    final state = await editFuture;

    expect(state.allocations.length, 2);
    expect(state.allocations.firstWhere((a) => a.invoiceId == 'inv_old').amountApplied, 400.0);
    // New invoice allocation should remain untouched (100.0) instead of being re-allocated to fill
    expect(state.allocations.firstWhere((a) => a.invoiceId == 'inv_new').amountApplied, 100.0);
    expect(state.hasManualOverride, true);
    expect(state.canSubmit, true);
  });

  test('canSubmit validates boundaries correctly', () async {
    final startFuture = bloc.stream.firstWhere((s) => !s.isLoading);
    bloc.add(ReceiptAllocationStarted(testCustomer));
    await startFuture;

    // Amount = 0
    expect(bloc.state.canSubmit, false);

    // Over-allocated beyond payment amount (Total allocated 650.0 > payment amount 600.0)
    final amountFuture1 = bloc.stream.first;
    bloc.add(const PaymentAmountChanged('600.00'));
    await amountFuture1;

    final editFuture1 = bloc.stream.first;
    bloc.add(const InvoiceAllocationEdited(
      invoiceId: 'inv_new',
      invoiceNumber: 'INV-102',
      value: '150.00', // old: 500, new: 150 -> 650
    ));
    var state = await editFuture1;
    expect(state.canSubmit, false);

    // Over-allocated single invoice beyond its balance (alloc 600.0 > balance 500.0)
    final amountFuture2 = bloc.stream.first;
    bloc.add(const PaymentAmountChanged('1000.00'));
    await amountFuture2;

    final editFuture2 = bloc.stream.first;
    bloc.add(const InvoiceAllocationEdited(
      invoiceId: 'inv_old',
      invoiceNumber: 'INV-101',
      value: '600.00',
    ));
    state = await editFuture2;
    expect(state.canSubmit, false);
  });

  test('Option B: Live refresh preserves manual overrides', () async {
    final startFuture = bloc.stream.firstWhere((s) => !s.isLoading);
    bloc.add(ReceiptAllocationStarted(testCustomer));
    await startFuture;

    // 1. User sets amount and edits allocation (manual override)
    final amountFuture = bloc.stream.first;
    bloc.add(const PaymentAmountChanged('600.00'));
    await amountFuture;

    final editFuture = bloc.stream.first;
    bloc.add(const InvoiceAllocationEdited(
      invoiceId: 'inv_old',
      invoiceNumber: 'INV-101',
      value: '400.00',
    ));
    await editFuture;

    // 2. Trigger live refresh simulation with a database state change
    salesRepo.openInvoices = [
      invoiceOld.copyWith(balance: 450.0),
      invoiceNew,
    ];
    final refreshFuture = bloc.stream.first;
    bloc.add(OpenInvoicesRefreshRequested());
    final state = await refreshFuture;

    // Verify manual override is preserved and capped if needed
    expect(state.hasManualOverride, true);
    expect(state.allocations.firstWhere((a) => a.invoiceId == 'inv_old').amountApplied, 400.0);
    expect(state.allocations.firstWhere((a) => a.invoiceId == 'inv_new').amountApplied, 100.0);
  });
}
