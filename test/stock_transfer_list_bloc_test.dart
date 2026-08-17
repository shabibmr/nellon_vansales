import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/submit_result.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/domain/repositories/stock_transfer_repository.dart';
import 'package:van_sales/ui/core/utils/date_filter.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_list_bloc.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_list_event.dart';

class _FakeStockTransferRepository implements StockTransferRepository {
  List<StockTransfer> local = [];
  List<StockTransfer> remote = [];
  Object? throwOnFetch;
  StockTransferDirection? lastDirection;
  DateTime? lastStart;
  DateTime? lastEnd;
  int fetchCalls = 0;

  @override
  List<StockTransfer> getLocalStockTransfers() => List.of(local);

  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
    required StockTransferDirection direction,
  }) async {
    fetchCalls++;
    lastDirection = direction;
    lastStart = startDate;
    lastEnd = endDate;
    if (throwOnFetch != null) throw throwOnFetch!;
    return remote.where((t) => t.direction == direction).toList();
  }

  @override
  Future<({List<Item> items, bool live})> loadCurrentLocationItems() async =>
      (items: <Item>[], live: false);

  @override
  List<Item> getItems() => [];

  @override
  Map<String, double> getTodaysInvoicedQuantities({DateTime? asOf}) => {};

  @override
  ({Warehouse defaultWarehouse, Warehouse currentLocation})
  resolveTransferLocations() => (
    defaultWarehouse: const Warehouse(id: '', name: '', address: ''),
    currentLocation: const Warehouse(id: '', name: '', address: ''),
  );

  @override
  Future<void> recordStockTransfer(StockTransfer transfer) async {}

  @override
  Future<void> enqueueStockTransfer(
    StockTransfer transfer, {
    required bool isUpdate,
  }) async {}

  @override
  Future<SubmitResult> submitStockTransfer(
    StockTransfer transfer, {
    bool isUpdate = false,
  }) async =>
      SubmitResult.queued;
}

StockTransfer _transfer({
  required String id,
  required StockTransferDirection direction,
  DateTime? date,
}) {
  return StockTransfer(
    id: id,
    transferNumber: id,
    date: date ?? todayDate(),
    direction: direction,
    fromLocationId: direction == StockTransferDirection.unload ? 'van' : 'wh',
    toLocationId: direction == StockTransferDirection.load ? 'van' : 'wh',
    lines: const [],
  );
}

void main() {
  late _FakeStockTransferRepository repo;
  late StockTransferListBloc bloc;

  setUp(() {
    repo = _FakeStockTransferRepository();
    bloc = StockTransferListBloc(stockTransferRepository: repo);
  });

  tearDown(() async => bloc.close());

  test('LoadStockTransfers fetches remote for the requested direction', () async {
    repo.remote = [
      _transfer(id: 'load_1', direction: StockTransferDirection.load),
      _transfer(id: 'unload_1', direction: StockTransferDirection.unload),
    ];

    bloc.add(const LoadStockTransfers(StockTransferDirection.load));
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(repo.lastDirection, StockTransferDirection.load);
    expect(bloc.state.direction, StockTransferDirection.load);
    expect(bloc.state.filteredTransfers.map((t) => t.id), ['load_1']);
  });

  test('remote failure falls back to local of the same direction + error', () async {
    repo.throwOnFetch = Exception('offline');
    repo.local = [
      _transfer(id: 'local_load', direction: StockTransferDirection.load),
      _transfer(id: 'local_unload', direction: StockTransferDirection.unload),
    ];

    bloc.add(const LoadStockTransfers(StockTransferDirection.load));
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.filteredTransfers.map((t) => t.id), ['local_load']);
    expect(bloc.state.errorMessage, isNotNull);
  });

  test('date filter change retriggers Zoho', () async {
    repo.remote = [
      _transfer(id: 'today', direction: StockTransferDirection.load),
    ];

    bloc.add(const LoadStockTransfers(StockTransferDirection.load));
    await bloc.stream.firstWhere((s) => !s.isLoading);

    final yesterday = todayDate().subtract(const Duration(days: 1));
    bloc.add(
      SetStockTransferDateFilter(startDate: yesterday, endDate: yesterday),
    );
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(repo.lastStart, yesterday);
    expect(repo.lastEnd, yesterday);
    expect(repo.fetchCalls, 2);
  });

  test('unload load never includes an issue transfer', () async {
    repo.remote = [
      _transfer(id: 'load_1', direction: StockTransferDirection.load),
      _transfer(id: 'unload_1', direction: StockTransferDirection.unload),
    ];

    bloc.add(const LoadStockTransfers(StockTransferDirection.unload));
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.filteredTransfers.map((t) => t.id), ['unload_1']);
  });
}
