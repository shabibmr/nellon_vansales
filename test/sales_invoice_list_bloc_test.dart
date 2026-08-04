import 'dart:async';

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
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_list_bloc.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_list_event.dart';

class RecordingSalesRepository implements SalesRepository {
  final List<({DateTime? start, DateTime? end})> fetchCalls = [];
  List<SalesInvoice> remoteInvoices = [];
  List<SalesInvoice> localInvoices = [];
  Object? fetchFailure;

  final List<Future<List<SalesInvoice>>> responseQueue = [];

  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    fetchCalls.add((start: startDate, end: endDate));
    if (responseQueue.isNotEmpty) {
      return responseQueue.removeAt(0);
    }
    if (fetchFailure != null) throw fetchFailure!;
    return List.of(remoteInvoices);
  }

  @override
  List<SalesInvoice> getLocalInvoices() => List.of(localInvoices);

  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId) async => null;
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}
  @override
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate}) async {}
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;
  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => [];
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
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId) async => null;
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
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(Item item) async =>
      (item: item, offlineFallback: false);
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
  CashClosing? getLocalCashClosing() => null;
  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}
  @override
  List<StockTransfer> getLocalStockTransfers() => [];
  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({DateTime? startDate, DateTime? endDate}) async => [];
}

class FakeSyncRepository implements SyncRepository {
  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {}
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

SalesInvoice _inv(String id, DateTime date) => SalesInvoice(
      id: id,
      invoiceNumber: 'INV-$id',
      customerId: 'cust_1',
      customerName: 'Acme',
      date: date,
      dueDate: date,
      items: const [],
      notes: '',
    );

void main() {
  late RecordingSalesRepository repo;
  late FakeSyncRepository syncRepo;
  late SalesInvoiceListBloc bloc;

  setUp(() {
    repo = RecordingSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = SalesInvoiceListBloc(
      salesRepository: repo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() async => bloc.close());

  test('LoadInvoices fetches remote with default today filter', () async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    repo.remoteInvoices = [_inv('1', today)];

    bloc.add(const LoadInvoices());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(repo.fetchCalls, hasLength(1));
    expect(bloc.state.invoices, hasLength(1));
    expect(bloc.state.errorMessage, isNull);
  });

  test('fetch failure falls back to local invoices with humanized error', () async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    repo.fetchFailure = Exception('connection reset');
    repo.localInvoices = [_inv('local', today)];

    bloc.add(const LoadInvoices());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.invoices.map((i) => i.id), ['local']);
    expect(bloc.state.errorMessage, isNotNull);
  });

  test('stale concurrent fetch does not overwrite newer results', () async {
    final startA = DateTime(2026, 1, 1);
    final endA = DateTime(2026, 1, 31);
    final startB = DateTime(2026, 6, 1);
    final endB = DateTime(2026, 6, 30);

    final slowA = Completer<List<SalesInvoice>>();
    final fastB = Completer<List<SalesInvoice>>();
    repo.responseQueue.addAll([slowA.future, fastB.future]);

    bloc.add(SetDateFilter(startDate: startA, endDate: endA));
    await Future<void>.delayed(Duration.zero);
    bloc.add(SetDateFilter(startDate: startB, endDate: endB));
    await Future<void>.delayed(Duration.zero);

    fastB.complete([_inv('june', startB)]);
    await bloc.stream.firstWhere(
      (s) => !s.isLoading && s.invoices.any((i) => i.id == 'june'),
    );

    slowA.complete([_inv('jan', startA)]);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.startDate, startB);
    expect(bloc.state.endDate, endB);
    expect(bloc.state.invoices.map((i) => i.id), ['june']);
    expect(bloc.state.isLoading, isFalse);
  });
}
