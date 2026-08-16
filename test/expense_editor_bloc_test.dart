import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
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
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_editor_bloc.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_editor_event.dart';

class FakeSalesRepository
    with SalesRepositoryEnqueueStubs
    implements SalesRepository {
  List<ExpenseEntry> expenses = [];
  List<SyncQueueItem> queue = [];

  @override
  List<ExpenseEntry> getLocalExpenses() => List.of(expenses);

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    expenses.add(expense);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      expenses;

  @override
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate}) async {}
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId, {bool allowOfflineFallback = false}) async => null;
  @override
  List<SalesInvoice> getLocalInvoices() => [];
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<ExpenseEntry?> fetchExpenseById(String expenseId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => List.of(queue);
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async => [];
  @override
  List<ReceiptVoucher> getLocalReceipts() => [];
  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {}
  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {}
  @override
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  }) async {}
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
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(Item item) async =>
      (item: item, offlineFallback: false);

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  ) async =>
      (customer: customer, offlineFallback: false);
  @override
  List<SalesReturn> getLocalReturns() => [];
  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}
  @override
  Future<List<SalesReturn>> fetchRemoteReturns({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  CashClosing? getLocalCashClosing() => null;
  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}
  @override
  List<StockTransfer> getLocalStockTransfers() => [];
  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<CustomerLedger> fetchCustomerLedger(String customerId, {DateTime? startDate, DateTime? endDate}) => throw UnimplementedError();
  @override
  Customer? getCustomerById(String id) => null;
  @override
  Organization? getOrganization() => null;
  @override
  String? get assignedWarehouseId => null;
  @override
  String? get primaryWarehouseId => null;
  @override
  List<Warehouse> getWarehouses() => [];
  @override
  bool hasPendingCashClosingForToday() => false;
  @override
  Future<List<Item>> fetchRemoteItems({String? locationId}) async => [];
  @override
  Future<void> pushCustomerGpsRemote(String customerId, double latitude, double longitude) => throw UnimplementedError();
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

  @override
  int getMasterRecordCount(MasterType type) => 0;
}

void main() {
  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late ExpenseEditorBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = ExpenseEditorBloc(
      salesRepository: salesRepo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() async => bloc.close());

  test('StartNewExpense initializes form defaults', () async {
    bloc.add(const StartNewExpense());
    final state = await bloc.stream.firstWhere((s) => s.isEditingNew);

    expect(state.isEditingNew, isTrue);
    expect(state.editingCategory, 'Fuel');
    expect(state.editingAmount, 0.0);
  });

  test('SaveExpense saves local expense entry and enqueues sync queue item', () async {
    bloc.add(const StartNewExpense());
    bloc.add(const SetEditingExpenseAmount(120.0));
    bloc.add(const SetEditingExpenseCategory('Maintenance'));
    bloc.add(const SetEditingExpenseDescription('Engine Oil'));
    bloc.add(const SaveExpense());

    await bloc.stream.firstWhere((s) => s.successMessage != null);

    expect(salesRepo.expenses, hasLength(1));
    final saved = salesRepo.expenses.single;
    expect(saved.amount, 120.0);
    expect(saved.lines.single.category, 'Maintenance');
    expect(saved.lines.single.description, 'Engine Oil');

    expect(salesRepo.queue, hasLength(1));
    expect(syncRepo.triggerCount, 1);
  });
}
