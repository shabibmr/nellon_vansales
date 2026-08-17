import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/submit_result.dart';
import 'package:van_sales/domain/models/warehouse.dart';
import 'package:van_sales/domain/repositories/stock_transfer_repository.dart';
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
  bool? lastIsUpdate;
  final List<SyncQueueItem> queue = [];

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

  @override
  Future<void> enqueueStockTransfer(
    StockTransfer transfer, {
    required bool isUpdate,
  }) async {
    recorded = transfer;
    queue.add(
      SyncQueueItem(
        id: transfer.id,
        type: isUpdate ? 'update_stock_transfer' : 'stock_transfer',
        payload: const <String, dynamic>{},
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<SubmitResult> submitStockTransfer(
    StockTransfer transfer, {
    bool isUpdate = false,
  }) async {
    lastIsUpdate = isUpdate;
    await enqueueStockTransfer(transfer, isUpdate: isUpdate);
    return SubmitResult.queued;
  }

  @override
  List<StockTransfer> getLocalStockTransfers() => [];

  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
    required StockTransferDirection direction,
  }) async =>
      [];
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

    setUp(() {
      stockTransferRepo = _FakeStockTransferRepository();
    });

    StockTransferBloc buildBloc() => StockTransferBloc(
      stockTransferRepository: stockTransferRepo,
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

      expect(state.successMessage, 'Saved to upload queue');
      expect(stockTransferRepo.recorded, isNotNull);
      expect(stockTransferRepo.recorded!.fromLocationId, 'van_1');
      expect(stockTransferRepo.recorded!.toLocationId, 'w1');
      expect(stockTransferRepo.recorded!.notes, 'end of trip');
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

    test('LoadIssueGridForEdit prefills extraQty from the transfer\'s own lines', () async {
      stockTransferRepo.liveItems = [item]; // current stock, extraQty starts 0
      final existing = StockTransfer(
        id: 'to_1',
        transferNumber: 'TO-1',
        date: DateTime(2026, 8, 1),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [
          StockTransferLine(item: item, quantity: 6, uom: 'pcs'),
        ],
        zohoTransferId: 'zoho_to_1',
        status: 'draft',
      );

      final bloc = buildBloc();
      bloc.add(LoadIssueGridForEdit(existing));
      final state = await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(state.rows, hasLength(1));
      expect(state.rows.single.extraQty, 6);
      expect(state.editingTransferId, 'to_1');
      expect(state.editingZohoTransferId, 'zoho_to_1');
      expect(state.status, 'draft');
      expect(state.isEditingExisting, isTrue);
      expect(state.isReadOnly, isFalse);
      bloc.close();
    });

    test('LoadIssueGridForEdit keeps a zero-stock line item from the transfer visible', () async {
      const zeroStockItem = Item(
        id: 'gone_item',
        name: 'No Longer In Stock',
        sku: 'SKUG',
        rate: 1.0,
        stock: 0,
        description: '',
        taxName: 'No Tax',
        taxPercentage: 0.0,
      );
      stockTransferRepo.liveItems = []; // not in current stock anymore
      final existing = StockTransfer(
        id: 'to_2',
        transferNumber: 'TO-2',
        date: DateTime(2026, 8, 1),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: zeroStockItem, quantity: 3)],
        zohoTransferId: 'zoho_to_2',
      );

      final bloc = buildBloc();
      bloc.add(LoadIssueGridForEdit(existing));
      final state = await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(state.rows, hasLength(1));
      expect(state.rows.single.item.id, 'gone_item');
      expect(state.rows.single.extraQty, 3);
      bloc.close();
    });

    test('LoadUnloadGridForEdit prefills extraQty from the transfer\'s own lines', () async {
      stockTransferRepo.localItems = [item];
      final existing = StockTransfer(
        id: 'to_3',
        transferNumber: 'TO-3',
        date: DateTime(2026, 8, 1),
        direction: StockTransferDirection.unload,
        fromLocationId: 'van_1',
        toLocationId: 'w1',
        lines: [StockTransferLine(item: item, quantity: 4)],
        zohoTransferId: 'zoho_to_3',
        status: 'transferred',
      );

      final bloc = buildBloc();
      bloc.add(LoadUnloadGridForEdit(existing));
      final state = await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(state.rows, hasLength(1));
      expect(state.rows.single.extraQty, 4);
      expect(state.status, 'transferred');
      expect(state.isReadOnly, isTrue);
      bloc.close();
    });

    test('SubmitTransfer in edit mode calls submitStockTransfer with isUpdate '
        'true and preserves id/zohoTransferId/number/date', () async {
      stockTransferRepo.liveItems = [item];
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
      final existing = StockTransfer(
        id: 'to_4',
        transferNumber: 'TO-4',
        date: DateTime(2026, 8, 1),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: item, quantity: 6)],
        zohoTransferId: 'zoho_to_4',
        status: 'draft',
      );

      final bloc = buildBloc();
      bloc.add(LoadIssueGridForEdit(existing));
      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(const SubmitTransfer(notes: 'updated notes'));
      final state = await bloc.stream.firstWhere(
        (s) => s.successMessage != null,
      );

      expect(state.successMessage, 'Saved to upload queue');
      expect(stockTransferRepo.recorded!.id, 'to_4');
      expect(stockTransferRepo.recorded!.zohoTransferId, 'zoho_to_4');
      expect(stockTransferRepo.recorded!.transferNumber, 'TO-4');
      expect(stockTransferRepo.recorded!.date, DateTime(2026, 8, 1));
      expect(stockTransferRepo.lastIsUpdate, isTrue);
      bloc.close();
    });

    test('SubmitTransfer is a no-op guard once the transfer is read-only', () async {
      final existing = StockTransfer(
        id: 'to_5',
        transferNumber: 'TO-5',
        date: DateTime(2026, 8, 1),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: item, quantity: 6)],
        zohoTransferId: 'zoho_to_5',
        status: 'transferred',
      );

      final bloc = buildBloc();
      bloc.add(LoadIssueGridForEdit(existing));
      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(const SubmitTransfer());
      final state = await bloc.stream.firstWhere(
        (s) => s.errorMessage != null,
      );

      expect(state.errorMessage, contains('already been processed'));
      expect(stockTransferRepo.recorded, isNull);
      bloc.close();
    });
  });
}
