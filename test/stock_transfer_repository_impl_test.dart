import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/stock_transfer_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
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
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db);

  bool shouldThrow = false;
  List<Map<String, dynamic>> remoteItems = [];

  @override
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    if (shouldThrow) throw Exception('network error');
    return remoteItems;
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
}
