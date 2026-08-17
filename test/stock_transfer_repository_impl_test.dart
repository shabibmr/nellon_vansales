import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/stock_transfer_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/salesperson.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/warehouse.dart';

class _FakeDb extends HiveDatabaseService {
  List<Warehouse> warehouses = [];
  String? primaryId;
  String? assignedId;
  List<Item> items = [];
  List<SalesInvoice> invoices = [];

  StockTransfer? savedTransfer;
  SyncQueueItem? enqueuedItem;
  Salesperson? salesperson;
  List<StockTransfer> localTransfers = [];
  List<StockTransfer>? savedRemote;
  int saveRemoteCalls = 0;

  @override
  List<Warehouse> getWarehouses() => warehouses;

  @override
  String? get primaryWarehouseId => primaryId;

  @override
  String? get assignedWarehouseId => assignedId;

  @override
  List<Item> getItems() => items;

  @override
  List<SalesInvoice> getLocalInvoices() => invoices;

  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {
    savedTransfer = transfer;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    enqueuedItem = item;
  }

  @override
  Salesperson? getCurrentSalesperson() => salesperson;

  @override
  List<StockTransfer> getLocalStockTransfers() => List.of(localTransfers);

  @override
  Future<void> saveRemoteStockTransfers(List<StockTransfer> remote) async {
    saveRemoteCalls++;
    savedRemote = remote;
    localTransfers = [
      ...localTransfers.where((t) => t.isPendingSync),
      ...remote,
    ];
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db);

  bool shouldThrow = false;
  List<Map<String, dynamic>> remoteItems = [];
  bool shouldThrowTransfers = false;
  List<Map<String, dynamic>> remoteTransfers = [];
  DateTime? lastStart;
  DateTime? lastEnd;
  String? lastFromLocationId;
  String? lastToLocationId;
  int fetchTransferCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    if (shouldThrow) throw Exception('network error');
    return remoteItems;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
    String? fromLocationId,
    String? toLocationId,
  }) async {
    fetchTransferCalls++;
    lastStart = startDate;
    lastEnd = endDate;
    lastFromLocationId = fromLocationId;
    lastToLocationId = toLocationId;
    if (shouldThrowTransfers) throw Exception('network error');
    return remoteTransfers;
  }
}

Item _item(String id, {double stock = 0}) => Item(
  id: id,
  name: 'Item $id',
  sku: 'SKU$id',
  rate: 10,
  stock: stock,
  description: '',
  taxName: 'No Tax',
  taxPercentage: 0,
);

Warehouse _warehouse(String id, {bool isPrimary = false}) =>
    Warehouse(id: id, name: 'Warehouse $id', address: '', isPrimary: isPrimary);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late StockTransferRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = StockTransferRepositoryImpl(dbService: db, apiClient: api);
  });

  group('resolveTransferLocations', () {
    test('no warehouses: default is placeholder, current is id-only placeholder', () {
      db.assignedId = 'van_1';
      final result = repo.resolveTransferLocations();
      expect(result.defaultWarehouse.id, '');
      expect(result.currentLocation.id, 'van_1');
    });

    test('primary-flag lookup falls back to first warehouse when none flagged primary', () {
      db.warehouses = [_warehouse('w1'), _warehouse('w2')];
      final result = repo.resolveTransferLocations();
      expect(result.defaultWarehouse.id, 'w1');
    });

    test('primaryWarehouseId, when it matches a warehouse, wins over the isPrimary flag', () {
      db.warehouses = [_warehouse('w1'), _warehouse('w2', isPrimary: true)];
      db.primaryId = 'w1';
      final result = repo.resolveTransferLocations();
      expect(result.defaultWarehouse.id, 'w1');
    });

    test('isPrimary flag wins when primaryWarehouseId is unset', () {
      db.warehouses = [_warehouse('w1'), _warehouse('w2', isPrimary: true)];
      final result = repo.resolveTransferLocations();
      expect(result.defaultWarehouse.id, 'w2');
    });

    test('assigned-id lookup returns the matching warehouse', () {
      db.warehouses = [_warehouse('w1'), _warehouse('van_1')];
      db.assignedId = 'van_1';
      final result = repo.resolveTransferLocations();
      expect(result.currentLocation.id, 'van_1');
    });

    test('assigned-id lookup falls back to an id-only placeholder when unmatched', () {
      db.warehouses = [_warehouse('w1')];
      db.assignedId = 'van_unknown';
      final result = repo.resolveTransferLocations();
      expect(result.currentLocation.id, 'van_unknown');
      expect(result.currentLocation.name, 'Current Location');
    });
  });

  group('getTodaysInvoicedQuantities', () {
    test('sums base-unit quantities per item, scoped to the target day', () {
      final today = DateTime(2026, 8, 16);
      final itemA = _item('a');
      db.invoices = [
        SalesInvoice(
          id: 'inv1',
          invoiceNumber: 'INV1',
          customerId: 'c1',
          customerName: 'Cust',
          date: today,
          dueDate: today,
          items: [
            InvoiceLineItem(item: itemA, quantity: 3, rate: 10, taxPercentage: 0),
          ],
          notes: '',
        ),
        SalesInvoice(
          id: 'inv2',
          invoiceNumber: 'INV2',
          customerId: 'c1',
          customerName: 'Cust',
          date: today,
          dueDate: today,
          items: [
            InvoiceLineItem(item: itemA, quantity: 2, rate: 10, taxPercentage: 0),
          ],
          notes: '',
        ),
        SalesInvoice(
          id: 'inv3',
          invoiceNumber: 'INV3',
          customerId: 'c1',
          customerName: 'Cust',
          date: today.subtract(const Duration(days: 1)),
          dueDate: today,
          items: [
            InvoiceLineItem(item: itemA, quantity: 100, rate: 10, taxPercentage: 0),
          ],
          notes: '',
        ),
      ];

      final result = repo.getTodaysInvoicedQuantities(asOf: today);
      expect(result['a'], 5);
    });
  });

  group('loadCurrentLocationItems', () {
    test('prefers the live fetch and reports live: true', () async {
      db.assignedId = 'van_1';
      api.remoteItems = [
        {'item_id': 'a', 'name': 'Item A', 'stock_on_hand': 7},
      ];
      db.items = [_item('a', stock: 999)]; // cache should NOT be used

      final result = await repo.loadCurrentLocationItems();
      expect(result.live, isTrue);
      expect(result.items, hasLength(1));
      expect(result.items.single.stock, 7);
    });

    test('falls back to the local cache when the live fetch fails', () async {
      api.shouldThrow = true;
      db.items = [_item('a', stock: 5)];

      final result = await repo.loadCurrentLocationItems();
      expect(result.live, isFalse);
      expect(result.items, db.items);
    });
  });

  group('recordStockTransfer', () {
    test('saves locally and enqueues a stock_transfer sync item', () async {
      final transfer = StockTransfer(
        id: 'temp_1',
        transferNumber: 'TO-TEMP-1',
        date: DateTime(2026, 8, 16),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: _item('a'), quantity: 4)],
      );

      await repo.recordStockTransfer(transfer);

      expect(db.savedTransfer, transfer);
      expect(db.enqueuedItem, isNotNull);
      expect(db.enqueuedItem!.id, 'temp_1');
      expect(db.enqueuedItem!.type, 'stock_transfer');
      expect(db.enqueuedItem!.status, SyncStatus.pending);
    });
  });

  group('enqueueStockTransfer / submitStockTransfer isUpdate', () {
    test('create writes a stock_transfer queue item with no transfer_order_id', () async {
      final transfer = StockTransfer(
        id: 'temp_1',
        transferNumber: 'TO-TEMP-1',
        date: DateTime(2026, 8, 16),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: _item('a'), quantity: 4)],
      );

      await repo.enqueueStockTransfer(transfer, isUpdate: false);

      expect(db.enqueuedItem!.type, 'stock_transfer');
      expect(db.enqueuedItem!.payload.containsKey('transfer_order_id'), isFalse);
    });

    test('update stamps transfer_order_id and uses update_stock_transfer type', () async {
      final transfer = StockTransfer(
        id: 'to_5',
        transferNumber: 'TO-5',
        date: DateTime(2026, 8, 16),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: _item('a'), quantity: 4)],
        zohoTransferId: 'zoho_to_5',
      );

      await repo.enqueueStockTransfer(transfer, isUpdate: true);

      expect(db.enqueuedItem!.type, 'update_stock_transfer');
      expect(db.enqueuedItem!.payload['transfer_order_id'], 'zoho_to_5');
    });

    test('update without a zohoTransferId throws', () async {
      final transfer = StockTransfer(
        id: 'to_6',
        transferNumber: 'TO-6',
        date: DateTime(2026, 8, 16),
        direction: StockTransferDirection.load,
        fromLocationId: 'w1',
        toLocationId: 'van_1',
        lines: [StockTransferLine(item: _item('a'), quantity: 4)],
      );

      expect(
        () => repo.enqueueStockTransfer(transfer, isUpdate: true),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('fetchRemoteStockTransfers', () {
    final start = DateTime(2026, 8, 16);
    final end = DateTime(2026, 8, 16);

    StockTransfer pendingUnload() => StockTransfer(
      id: 'temp_unload',
      transferNumber: 'TO-TEMP-U',
      date: start,
      direction: StockTransferDirection.unload,
      fromLocationId: 'van_1',
      toLocationId: 'wh',
      lines: [StockTransferLine(item: _item('a'), quantity: 1)],
      isPendingSync: true,
    );

    test('issue fetch sends to_location_id and stamps load', () async {
      db.salesperson = const Salesperson(
        id: 'sp',
        name: 'Sam',
        email: '',
        locationId: 'van_1',
      );
      api.remoteTransfers = [
        {
          'transfer_order_id': 'to_1',
          'transfer_order_number': 'TO-1',
          'date': '2026-08-16',
          'from_location_id': 'wh',
          'to_location_id': 'van_1',
          'line_items': <Map<String, dynamic>>[],
        },
      ];

      final result = await repo.fetchRemoteStockTransfers(
        startDate: start,
        endDate: end,
        direction: StockTransferDirection.load,
      );

      expect(api.lastToLocationId, 'van_1');
      expect(api.lastFromLocationId, isNull);
      expect(api.lastStart, start);
      expect(api.lastEnd, end);
      expect(result, hasLength(1));
      expect(result.single.direction, StockTransferDirection.load);
      expect(db.saveRemoteCalls, 1);
      expect(db.savedRemote!.single.direction, StockTransferDirection.load);
    });

    test('fetch parses the Zoho status field onto the local transfer', () async {
      db.salesperson = const Salesperson(
        id: 'sp',
        name: 'Sam',
        email: '',
        locationId: 'van_1',
      );
      api.remoteTransfers = [
        {
          'transfer_order_id': 'to_1',
          'transfer_order_number': 'TO-1',
          'date': '2026-08-16',
          'from_location_id': 'wh',
          'to_location_id': 'van_1',
          'status': 'transferred',
          'line_items': <Map<String, dynamic>>[],
        },
      ];

      final result = await repo.fetchRemoteStockTransfers(
        startDate: start,
        endDate: end,
        direction: StockTransferDirection.load,
      );

      expect(result.single.status, 'transferred');
      expect(result.single.isEditable, isFalse);
    });

    test('unload fetch sends from_location_id and stamps unload', () async {
      db.assignedId = 'van_1';
      api.remoteTransfers = [
        {
          'transfer_order_id': 'to_2',
          'transfer_order_number': 'TO-2',
          'date': '2026-08-16',
          'from_location_id': 'van_1',
          'to_location_id': 'wh',
          'line_items': <Map<String, dynamic>>[],
        },
      ];

      final result = await repo.fetchRemoteStockTransfers(
        startDate: start,
        endDate: end,
        direction: StockTransferDirection.unload,
      );

      expect(api.lastFromLocationId, 'van_1');
      expect(api.lastToLocationId, isNull);
      expect(result.single.direction, StockTransferDirection.unload);
    });

    test('missing location does not call Zoho', () async {
      expect(
        () => repo.fetchRemoteStockTransfers(
          direction: StockTransferDirection.load,
        ),
        throwsA(isA<Exception>()),
      );
      expect(api.fetchTransferCalls, 0);
    });

    test('saveRemote does not go through saveLocalStockTransfer', () async {
      db.salesperson = const Salesperson(
        id: 'sp',
        name: 'Sam',
        email: '',
        locationId: 'van_1',
      );
      api.remoteTransfers = [
        {
          'transfer_order_id': 'to_1',
          'transfer_order_number': 'TO-1',
          'date': '2026-08-16',
          'from_location_id': 'wh',
          'to_location_id': 'van_1',
        },
      ];

      await repo.fetchRemoteStockTransfers(
        direction: StockTransferDirection.load,
      );

      expect(db.savedTransfer, isNull);
      expect(db.saveRemoteCalls, 1);
    });

    test('drops the opposite direction when Zoho returns mixed rows', () async {
      db.salesperson = const Salesperson(
        id: 'sp',
        name: 'Sam',
        email: '',
        locationId: 'van_1',
      );
      api.remoteTransfers = [
        {
          'transfer_order_id': 'issue_1',
          'transfer_order_number': 'TO-I',
          'date': '2026-08-16',
          'from_location_id': 'wh',
          'to_location_id': 'van_1',
        },
        {
          'transfer_order_id': 'unload_1',
          'transfer_order_number': 'TO-U',
          'date': '2026-08-16',
          'from_location_id': 'van_1',
          'to_location_id': 'wh',
        },
      ];

      final result = await repo.fetchRemoteStockTransfers(
        direction: StockTransferDirection.load,
      );

      expect(result.map((t) => t.id), ['issue_1']);
    });

    test('keeps pending locals of the requested direction after merge', () async {
      db.salesperson = const Salesperson(
        id: 'sp',
        name: 'Sam',
        email: '',
        locationId: 'van_1',
      );
      db.localTransfers = [pendingUnload()];
      api.remoteTransfers = [
        {
          'transfer_order_id': 'to_2',
          'transfer_order_number': 'TO-2',
          'date': '2026-08-16',
          'from_location_id': 'van_1',
          'to_location_id': 'wh',
        },
      ];

      final result = await repo.fetchRemoteStockTransfers(
        direction: StockTransferDirection.unload,
      );

      expect(result.map((t) => t.id), containsAll(['temp_unload', 'to_2']));
    });
  });
}
