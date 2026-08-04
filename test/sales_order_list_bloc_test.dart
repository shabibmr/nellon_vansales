import 'dart:async';

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
import 'package:van_sales/ui/features/sales_order/bloc/sales_order_list_bloc.dart';
import 'package:van_sales/ui/features/sales_order/bloc/sales_order_list_event.dart';

class RecordingSalesRepository implements SalesRepository {
  final List<({DateTime? start, DateTime? end})> fetchCalls = [];
  List<SalesOrder> remoteOrders = [];
  List<SalesOrder> localOrders = [];
  Object? fetchFailure;

  /// When non-empty, each fetch awaits/removes the next future (for race tests).
  final List<Future<List<SalesOrder>>> responseQueue = [];

  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    fetchCalls.add((start: startDate, end: endDate));
    if (responseQueue.isNotEmpty) {
      return responseQueue.removeAt(0);
    }
    if (fetchFailure != null) throw fetchFailure!;
    return List.of(remoteOrders);
  }

  @override
  List<SalesOrder> getLocalOrders() => List.of(localOrders);

  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}
  @override
  Future<void> enqueueSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  }) async {}
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
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => [];
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({
    String? customerId,
  }) async => [];
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
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(
    Item item,
  ) async => (item: item, offlineFallback: false);
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

SalesOrder _order(String id, DateTime date) => SalesOrder(
  id: id,
  orderNumber: 'SO-$id',
  customerId: 'c1',
  customerName: 'Acme',
  date: date,
  shipmentDate: date,
  items: const [],
  notes: '',
);

void main() {
  late RecordingSalesRepository repo;
  late SalesOrderListBloc bloc;

  setUp(() {
    repo = RecordingSalesRepository();
    bloc = SalesOrderListBloc(salesRepository: repo);
  });

  tearDown(() async => bloc.close());

  test('LoadSalesOrders fetches remote with default today filter', () async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    repo.remoteOrders = [_order('1', today)];

    bloc.add(const LoadSalesOrders());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(repo.fetchCalls, hasLength(1));
    expect(repo.fetchCalls.single.start, today);
    expect(repo.fetchCalls.single.end, today);
    expect(bloc.state.orders, hasLength(1));
    expect(bloc.state.errorMessage, isNull);
  });

  test('fetch failure falls back to local orders with humanized error', () async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    repo.fetchFailure = Exception('socket hang up');
    repo.localOrders = [_order('local', today)];

    bloc.add(const LoadSalesOrders());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.orders.map((o) => o.id), ['local']);
    expect(bloc.state.errorMessage, isNotNull);
    expect(bloc.state.errorMessage, isNot(contains('Exception:')));
  });

  test('SetSalesOrderDateFilter reloads with the new range', () async {
    final start = DateTime(2026, 6, 1);
    final end = DateTime(2026, 6, 30);
    repo.remoteOrders = [_order('june', start)];

    bloc.add(SetSalesOrderDateFilter(startDate: start, endDate: end));
    await bloc.stream.firstWhere(
      (s) =>
          !s.isLoading &&
          s.startDate == start &&
          s.endDate == end &&
          s.orders.isNotEmpty,
    );

    expect(repo.fetchCalls, isNotEmpty);
    final last = repo.fetchCalls.last;
    expect(last.start, start);
    expect(last.end, end);
    expect(bloc.state.orders.single.id, 'june');
  });

  test('ClearSalesOrderListMessages clears error', () async {
    repo.fetchFailure = Exception('offline');
    bloc.add(const LoadSalesOrders());
    await bloc.stream.firstWhere((s) => s.errorMessage != null);

    bloc.add(const ClearSalesOrderListMessages());
    await bloc.stream.firstWhere((s) => s.errorMessage == null);

    expect(bloc.state.errorMessage, isNull);
  });

  test('stale concurrent fetch does not overwrite newer results', () async {
    final startA = DateTime(2026, 1, 1);
    final endA = DateTime(2026, 1, 31);
    final startB = DateTime(2026, 6, 1);
    final endB = DateTime(2026, 6, 30);

    final slowA = Completer<List<SalesOrder>>();
    final fastB = Completer<List<SalesOrder>>();
    repo.responseQueue.addAll([slowA.future, fastB.future]);

    bloc.add(SetSalesOrderDateFilter(startDate: startA, endDate: endA));
    // Let the first handler reach its await.
    await Future<void>.delayed(Duration.zero);
    bloc.add(SetSalesOrderDateFilter(startDate: startB, endDate: endB));
    await Future<void>.delayed(Duration.zero);

    // Newer range finishes first.
    fastB.complete([_order('june', startB)]);
    await bloc.stream.firstWhere(
      (s) => !s.isLoading && s.orders.any((o) => o.id == 'june'),
    );

    // Older range completes late — must not clobber June results.
    slowA.complete([_order('jan', startA)]);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.startDate, startB);
    expect(bloc.state.endDate, endB);
    expect(bloc.state.orders.map((o) => o.id), ['june']);
    expect(bloc.state.isLoading, isFalse);
    expect(repo.fetchCalls, hasLength(2));
  });
}
