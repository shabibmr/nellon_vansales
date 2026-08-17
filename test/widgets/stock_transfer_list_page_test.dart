import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/submit_result.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/domain/models/paired_printer.dart';
import 'package:van_sales/domain/models/thermal_paper_size.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/session_repository.dart';
import 'package:van_sales/domain/repositories/stock_transfer_repository.dart';
import 'package:van_sales/domain/repositories/thermal_printer_repository.dart';
import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';
import 'package:van_sales/ui/core/widgets/document_list_card.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_list_bloc.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_list_event.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_list_state.dart';
import 'package:van_sales/ui/features/stock_transfer/views/issue_to_van_page.dart';
import 'package:van_sales/ui/features/stock_transfer/views/stock_transfer_list_page.dart';
import 'package:van_sales/ui/features/thermal_print/cubit/thermal_printer_cubit.dart';

class _FakeListBloc extends Fake implements StockTransferListBloc {
  _FakeListBloc(this._state);

  final StockTransferListState _state;
  final _controller = StreamController<StockTransferListState>.broadcast();

  @override
  StockTransferListState get state => _state;

  @override
  Stream<StockTransferListState> get stream => _controller.stream;

  @override
  void add(StockTransferListEvent event) {}

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _FakeTransferRepo implements StockTransferRepository {
  @override
  Future<({List<Item> items, bool live})> loadCurrentLocationItems() async =>
      (items: const <Item>[], live: false);

  @override
  List<Item> getItems() => const [];

  @override
  Map<String, double> getTodaysInvoicedQuantities({DateTime? asOf}) => const {};

  @override
  ({Warehouse defaultWarehouse, Warehouse currentLocation})
  resolveTransferLocations() => (
    defaultWarehouse: const Warehouse(id: 'wh', name: 'Main', address: ''),
    currentLocation: const Warehouse(id: 'van', name: 'Van', address: ''),
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
  }) async => SubmitResult.queued;

  @override
  List<StockTransfer> getLocalStockTransfers() => const [];

  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
    required StockTransferDirection direction,
  }) async =>
      const [];
}

StockTransfer _transfer() {
  const item = Item(
    id: 'item_1',
    name: 'Ghee',
    sku: 'SKU1',
    rate: 10,
    stock: 1,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );
  return StockTransfer(
    id: 'to_1',
    transferNumber: 'TO-1001',
    date: DateTime(2026, 8, 16),
    direction: StockTransferDirection.load,
    fromLocationId: 'wh',
    toLocationId: 'van',
    lines: const [StockTransferLine(item: item, quantity: 4)],
  );
}

class _FakeVoucherPdfRepo extends Fake implements VoucherPdfRepository {}
class _FakeCustomerRepo extends Fake implements CustomerRepository {}
class _FakeSessionRepo extends Fake implements SessionRepository {
  @override
  bool isCashClosingPending() => false;
}
class _FakeThermalPrinterRepo extends Fake implements ThermalPrinterRepository {
  @override
  ThermalPaperSize get paperSize => ThermalPaperSize.inch4;
  @override
  PairedPrinter? get preferredPrinter => null;
}

Widget _harness({
  required _FakeListBloc listBloc,
  StockTransferDirection direction = StockTransferDirection.load,
}) {
  // Providers must wrap MaterialApp (not just `home`) so they stay in scope
  // for pages pushed onto the Navigator later, not just the initial route.
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<StockTransferRepository>(
        create: (_) => _FakeTransferRepo(),
      ),
      RepositoryProvider<VoucherPdfRepository>(
        create: (_) => _FakeVoucherPdfRepo(),
      ),
      RepositoryProvider<CustomerRepository>(
        create: (_) => _FakeCustomerRepo(),
      ),
      RepositoryProvider<SessionRepository>(
        create: (_) => _FakeSessionRepo(),
      ),
      RepositoryProvider<ThermalPrinterRepository>(
        create: (_) => _FakeThermalPrinterRepo(),
      ),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<StockTransferListBloc>.value(
          value: listBloc,
        ),
        BlocProvider<ThermalPrinterCubit>(
          create: (_) => ThermalPrinterCubit(
            repository: _FakeThermalPrinterRepo(),
          ),
        ),
      ],
      child: MaterialApp(
        home: StockTransferListPage(direction: direction),
      ),
    ),
  );
}

void main() {
  testWidgets('Issue list shows title, empty state, and FAB', (tester) async {
    final listBloc = _FakeListBloc(
      StockTransferListState(
        direction: StockTransferDirection.load,
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 8, 16),
      ),
    );
    await tester.pumpWidget(_harness(listBloc: listBloc));

    expect(find.text('Issue to Van'), findsWidgets);
    expect(find.text('No Issue to Van transfers'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await listBloc.close();
  });

  testWidgets('list renders a header card and opens the transfer on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transfer = _transfer();
    final listBloc = _FakeListBloc(
      StockTransferListState(
        direction: StockTransferDirection.load,
        transfers: [transfer],
        startDate: DateTime(2026, 8, 16),
        endDate: DateTime(2026, 8, 16),
      ),
    );
    await tester.pumpWidget(_harness(listBloc: listBloc));

    expect(find.text('TO-1001'), findsOneWidget);
    expect(find.byType(DocumentListCard), findsOneWidget);

    await tester.tap(find.byType(DocumentListCard));
    await tester.pumpAndSettle();

    expect(find.byType(IssueToVanPage), findsOneWidget);

    await listBloc.close();
  });

  testWidgets('Unload list uses its own title and empty copy', (tester) async {
    final listBloc = _FakeListBloc(
      const StockTransferListState(
        direction: StockTransferDirection.unload,
      ),
    );
    await tester.pumpWidget(
      _harness(
        listBloc: listBloc,
        direction: StockTransferDirection.unload,
      ),
    );

    expect(find.text('Stock Unloading'), findsWidgets);
    expect(find.text('No Stock Unloading transfers'), findsOneWidget);

    await listBloc.close();
  });
}
