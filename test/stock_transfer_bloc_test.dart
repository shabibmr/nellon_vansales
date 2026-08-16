import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/domain/repositories/stock_transfer_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_bloc.dart';

class _FakeStockTransferRepository implements StockTransferRepository {
  List<Item> localItems = [];
  List<Item> liveItems = [];
  bool liveFetchSucceeds = true;
  Map<String, double> invoicedQty = {};
  Warehouse defaultWarehouse = const Warehouse(
    id: '',
    name: 'Default Warehouse',
    address: '',
  );
  Warehouse currentLocation = const Warehouse(
    id: '',
    name: 'Current Location',
    address: '',
  );

  StockTransfer? recorded;

  @override
  Future<({List<Item> items, bool live})> loadCurrentLocationItems() async {
    if (liveFetchSucceeds) return (items: liveItems, live: true);
    return (items: localItems, live: false);
  }

  @override
  List<Item> getItems() => localItems;

  @override
  Map<String, double> getTodaysInvoicedQuantities({DateTime? asOf}) =>
      invoicedQty;

  @override
  ({Warehouse defaultWarehouse, Warehouse currentLocation})
  resolveTransferLocations() =>
      (defaultWarehouse: defaultWarehouse, currentLocation: currentLocation);

  @override
  Future<void> recordStockTransfer(StockTransfer transfer) async {
    recorded = transfer;
  }
}

class _FakeSyncRepository implements SyncRepository {
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
  const item = Item(
    id: 'item_1',
    name: 'Item One',
    sku: 'SKU1',
    rate: 10.0,
    stock: 10,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0.0,
  );

  group('StockTransferRow column math', () {
    test('subtotal (Col 3) is current stock plus today\'s invoiced quantity', () {
      const row = StockTransferRow(item: item, currentStock: 20, invoiceQty: 8);
      expect(row.subtotal, equals(28));
    });

    test('grandTotal (Col 5) adds the editable extra quantity on top of subtotal', () {
      const row = StockTransferRow(
        item: item,
        currentStock: 20,
        invoiceQty: 8,
        extraQty: 5,
      );
      expect(row.subtotal, equals(28));
      expect(row.grandTotal, equals(33));
    });

    test('a brand-new row (no current stock, no invoices) still totals correctly', () {
      const row = StockTransferRow(item: item, currentStock: 0, extraQty: 12);
      expect(row.subtotal, equals(0));
      expect(row.grandTotal, equals(12));
    });
  });

  group('StockTransferState.transferQtyFor', () {
    test(
      'load direction transfers invoiceQty + extraQty, excluding current stock '
      'already on the van',
      () {
        const row = StockTransferRow(
          item: item,
          currentStock: 20,
          invoiceQty: 8,
          extraQty: 5,
        );
        const state = StockTransferState(
          direction: StockTransferDirection.load,
          rows: [row],
        );
        expect(state.transferQtyFor(row), equals(13));
        expect(state.totalTransferQty, equals(13));
      },
    );

    test('unload direction transfers only the editable extraQty (the balance to return)', () {
      const row = StockTransferRow(
        item: item,
        currentStock: 20,
        invoiceQty: 8, // irrelevant for unload
        extraQty: 15,
      );
      const state = StockTransferState(
        direction: StockTransferDirection.unload,
        rows: [row],
      );
      expect(state.transferQtyFor(row), equals(15));
      expect(state.totalTransferQty, equals(15));
    });

    test('totalTransferQty sums across multiple rows', () {
      const item2 = Item(
        id: 'item_2',
        name: 'Item Two',
        sku: 'SKU2',
        rate: 5.0,
        stock: 4,
        description: '',
        taxName: 'No Tax',
        taxPercentage: 0.0,
      );
      const rows = [
        StockTransferRow(item: item, currentStock: 20, invoiceQty: 8, extraQty: 5),
        StockTransferRow(item: item2, currentStock: 4, invoiceQty: 2, extraQty: 0),
      ];
      const state = StockTransferState(
        direction: StockTransferDirection.load,
        rows: rows,
      );
      // (8+5) + (2+0) = 15
      expect(state.totalTransferQty, equals(15));
    });

    test('a row with zero transfer quantity is excluded when building submit lines', () {
      const zeroRow = StockTransferRow(item: item, currentStock: 5);
      const state = StockTransferState(
        direction: StockTransferDirection.load,
        rows: [zeroRow],
      );
      expect(state.transferQtyFor(zeroRow), equals(0));
      final linesToTransfer =
          state.rows.where((r) => state.transferQtyFor(r) > 0).toList();
      expect(linesToTransfer, isEmpty);
    });
  });

  group('buildIssueToVanRows', () {
    const zeroStock = Item(
      id: 'item_zero',
      name: 'Zero Stock',
      sku: 'SKU0',
      rate: 1.0,
      stock: 0,
      description: '',
      taxName: 'No Tax',
      taxPercentage: 0.0,
    );
    const soldOut = Item(
      id: 'item_sold',
      name: 'Sold Out Today',
      sku: 'SKUS',
      rate: 1.0,
      stock: 0,
      description: '',
      taxName: 'No Tax',
      taxPercentage: 0.0,
    );
    const inStockB = Item(
      id: 'item_b',
      name: 'Bravo Item',
      sku: 'SKUB',
      rate: 1.0,
      stock: 4,
      description: '',
      taxName: 'No Tax',
      taxPercentage: 0.0,
    );

    test('omits zero-stock items that have no invoice or demand qty', () {
      final rows = buildIssueToVanRows(
        [item, zeroStock, inStockB],
        const {},
      );
      expect(rows.map((r) => r.item.id), equals(['item_b', 'item_1']));
    });

    test('keeps a sold-out item when it has invoice or demand qty', () {
      final rows = buildIssueToVanRows(
        [zeroStock, soldOut],
        const {'item_sold': 6},
      );
      expect(rows, hasLength(1));
      expect(rows.single.item.id, 'item_sold');
      expect(rows.single.currentStock, 0);
      expect(rows.single.invoiceQty, 6);
    });

    test('sorts remaining rows by item name', () {
      final rows = buildIssueToVanRows([item, inStockB], const {});
      expect(rows.map((r) => r.item.name), equals(['Bravo Item', 'Item One']));
    });
  });

  group('StockTransferBloc', () {
    late _FakeStockTransferRepository stockTransferRepo;
    late _FakeSyncRepository syncRepo;

    setUp(() {
      stockTransferRepo = _FakeStockTransferRepository();
      syncRepo = _FakeSyncRepository();
    });

    StockTransferBloc buildBloc() => StockTransferBloc(
      stockTransferRepository: stockTransferRepo,
      syncRepository: syncRepo,
    );

    test('SubmitTransfer with no lines fails validation', () async {
      final bloc = buildBloc();
      bloc.add(const SubmitTransfer());

      final state = await bloc.stream.firstWhere(
        (s) => s.errorMessage != null,
      );
      expect(
        state.errorMessage,
        'Please enter a quantity for at least one item',
      );
      bloc.close();
    });

    test('SubmitTransfer fails when the primary warehouse is unconfigured', () async {
      stockTransferRepo.localItems = [item];
      stockTransferRepo.defaultWarehouse = const Warehouse(
        id: '',
        name: 'Default Warehouse',
        address: '',
      );
      stockTransferRepo.currentLocation = const Warehouse(
        id: 'van_1',
        name: 'Van',
        address: '',
      );

      final bloc = buildBloc();
      bloc.add(LoadUnloadGrid());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(const SubmitTransfer());
      final state = await bloc.stream.firstWhere(
        (s) => s.errorMessage != null,
      );
      expect(state.errorMessage, contains('Primary location is not configured'));
      bloc.close();
    });

    test('SubmitTransfer fails when the van location is unresolved', () async {
      stockTransferRepo.localItems = [item];
      stockTransferRepo.defaultWarehouse = const Warehouse(
        id: 'w1',
        name: 'Warehouse',
        address: '',
      );
      stockTransferRepo.currentLocation = const Warehouse(
        id: '',
        name: 'Current Location',
        address: '',
      );

      final bloc = buildBloc();
      bloc.add(LoadUnloadGrid());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(const SubmitTransfer());
      final state = await bloc.stream.firstWhere(
        (s) => s.errorMessage != null,
      );
      expect(
        state.errorMessage,
        contains('Unable to resolve your van location'),
      );
      bloc.close();
    });

    test('SubmitTransfer records the transfer and triggers sync on success', () async {
      stockTransferRepo.localItems = [item];
      stockTransferRepo.defaultWarehouse = const Warehouse(
        id: 'w1',
        name: 'Warehouse',
        address: '',
      );
      stockTransferRepo.currentLocation = const Warehouse(
        id: 'van_1',
        name: 'Van',
        address: '',
      );

      final bloc = buildBloc();
      bloc.add(LoadUnloadGrid());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(const SubmitTransfer(notes: 'end of trip'));
      final state = await bloc.stream.firstWhere(
        (s) => s.successMessage != null,
      );

      expect(state.successMessage, 'Stock unloaded successfully');
      expect(stockTransferRepo.recorded, isNotNull);
      expect(stockTransferRepo.recorded!.fromLocationId, 'van_1');
      expect(stockTransferRepo.recorded!.toLocationId, 'w1');
      expect(stockTransferRepo.recorded!.notes, 'end of trip');
      expect(syncRepo.triggerCount, 1);
      bloc.close();
    });

    test('LoadIssueGrid reflects the repository\'s live flag', () async {
      stockTransferRepo.liveFetchSucceeds = false;
      stockTransferRepo.localItems = [item];

      final bloc = buildBloc();
      bloc.add(LoadIssueGrid());
      final state = await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(state.isLiveData, isFalse);
      bloc.close();
    });

    test('LoadIssueGridWithDemand unions live stock with cached demand items', () async {
      const demandItem = Item(
        id: 'demand_item',
        name: 'Demand Only',
        sku: 'SKUD',
        rate: 1.0,
        stock: 0,
        description: '',
        taxName: 'No Tax',
        taxPercentage: 0.0,
      );
      stockTransferRepo.liveItems = []; // nothing in stock at the live location
      stockTransferRepo.localItems = [demandItem]; // but cached with demand

      final bloc = buildBloc();
      bloc.add(const LoadIssueGridWithDemand({'demand_item': 5}));
      final state = await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(state.isLiveData, isTrue);
      expect(state.rows, hasLength(1));
      expect(state.rows.single.item.id, 'demand_item');
      expect(state.rows.single.currentStock, 0);
      expect(state.rows.single.invoiceQty, 5);
      bloc.close();
    });
  });
}
