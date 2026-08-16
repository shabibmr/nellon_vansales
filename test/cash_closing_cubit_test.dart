import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/ui/features/dashboard/cubit/cash_closing_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/cash_closing_state.dart';

class FakeSalesRepository implements SalesRepository {
  CashClosing? savedCashClosing;
  List<SyncQueueItem> syncQueue = [];
  bool shouldThrow = false;

  @override
  CashClosing? getLocalCashClosing() => savedCashClosing;

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {
    if (shouldThrow) throw Exception('Cash closing save failed');
    savedCashClosing = closing;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    if (shouldThrow) throw Exception('Queue enqueue failed');
    syncQueue.add(item);
  }

  // Stubs for remaining SalesRepository interface methods
  @override
  List<RouteModel> getRoutes() => [];
  @override
  String? get activeRouteId => null;
  @override
  Future<void> setActiveRouteId(String? routeId) async {}
  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
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
  List<Item> getItems() => [];
  @override
  Future<void> saveItems(List<Item> items) async {}
  @override
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(Item item) async => (item: item, offlineFallback: false);

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(Customer customer) async => (customer: customer, offlineFallback: false);
  @override
  List<SalesInvoice> getLocalInvoices() => [];
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<ExpenseEntry?> fetchExpenseById(String expenseId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate}) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId, {bool allowOfflineFallback = false}) async => null;
  @override
  List<ReceiptVoucher> getLocalReceipts() => [];
  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  List<SalesReturn> getLocalReturns() => [];
  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}
  @override
  Future<List<SalesReturn>> fetchRemoteReturns({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  List<ExpenseEntry> getLocalExpenses() => [];
  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {}
  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  List<SyncQueueItem> getSyncQueue() => syncQueue;
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async => [];
  @override
  List<StockTransfer> getLocalStockTransfers() => [];
  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({DateTime? startDate, DateTime? endDate}) async => [];

  @override
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      CustomerLedger(
        customerId: customerId,
        customerName: '',
        openingBalance: 0,
        closingBalance: 0,
        transactions: const [],
      );

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
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  ) async {}
}

class FakeSyncRepository implements SyncRepository {
  bool syncTriggered = false;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    syncTriggered = true;
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
  late CashClosingCubit cubit;

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    cubit = CashClosingCubit(
      salesRepository: salesRepo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() {
    cubit.close();
  });

  test('Initial state is CashClosingInitial', () {
    expect(cubit.state, isA<CashClosingInitial>());
  });

  test('submitCashClosing saves closing, enqueues sync, triggers sync, and emits CashClosingSuccess', () async {
    final expectedStates = [
      isA<CashClosingSubmitting>(),
      isA<CashClosingSuccess>(),
    ];

    expectLater(cubit.stream, emitsInOrder(expectedStates));

    await cubit.submitCashClosing(
      todaySales: 5000.0,
      todayPayments: 3000.0,
      todayExpenses: 200.0,
      physicalCashCounted: 3800.0, // Expected: 1000 + 3000 - 200 = 3800 => 0 diff
      notes: 'All balanced',
      openingBalance: 1000.0,
    );

    expect(salesRepo.savedCashClosing, isNotNull);
    final closing = salesRepo.savedCashClosing!;
    expect(closing.totalSalesInvoices, 5000.0);
    expect(closing.totalReceiptsCollected, 3000.0);
    expect(closing.totalExpenses, 200.0);
    expect(closing.closingBalance, 3800.0);
    expect(closing.reportedDifference, 0.0);
    expect(closing.notes, 'All balanced');

    expect(salesRepo.syncQueue.length, 1);
    expect(salesRepo.syncQueue.first.type, 'expense');

    expect(syncRepo.syncTriggered, true);
  });

  test('submitCashClosing handles exception and emits CashClosingFailure', () async {
    salesRepo.shouldThrow = true;

    final expectedStates = [
      isA<CashClosingSubmitting>(),
      isA<CashClosingFailure>(),
    ];

    expectLater(cubit.stream, emitsInOrder(expectedStates));

    await cubit.submitCashClosing(
      todaySales: 1000.0,
      todayPayments: 500.0,
      todayExpenses: 50.0,
      physicalCashCounted: 1450.0,
      notes: 'Failed test',
      openingBalance: 0,
    );

    final state = cubit.state;
    expect(state, isA<CashClosingFailure>());
    expect((state as CashClosingFailure).message, contains('Cash closing save failed'));
  });
}
