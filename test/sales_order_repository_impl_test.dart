import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/sales_order_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/sales_order.dart';

class _FakeDb extends HiveDatabaseService {
  List<SalesOrder> localOrders = [];
  List<SalesOrder> savedRemote = [];
  SalesOrder? savedLocal;
  SyncQueueItem? enqueued;
  String? assignedWarehouse;

  @override
  List<SalesOrder> getLocalOrders() => localOrders;

  @override
  Future<void> saveLocalOrder(SalesOrder order) async {
    savedLocal = order;
  }

  @override
  Future<void> saveRemoteOrders(
    List<SalesOrder> remote, {
    bool pruneMissingInRange = false,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    savedRemote = remote;
    localOrders = remote;
  }

  @override
  String? get assignedWarehouseId => assignedWarehouse;

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    enqueued = item;
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db, mockLatency: Duration.zero);

  bool throwOnDetail = false;
  Map<String, dynamic> detailResponse = {};
  List<Map<String, dynamic>> headersResponse = [];

  @override
  Future<Map<String, dynamic>> fetchSalesOrder(String salesOrderId) async {
    if (throwOnDetail) throw Exception('offline');
    return detailResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSalesOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async => headersResponse;
}

SalesOrder _order(String id, {String? zohoOrderId}) => SalesOrder(
  id: id,
  orderNumber: 'SO-1',
  customerId: 'c1',
  customerName: 'Cust',
  date: DateTime(2026, 8, 16),
  shipmentDate: DateTime(2026, 8, 18),
  items: const [],
  notes: '',
  zohoOrderId: zohoOrderId,
);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late SalesOrderRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = SalesOrderRepositoryImpl(dbService: db, apiClient: api);
  });

  test('getLocalOrders / saveLocalOrder delegate to dbService', () async {
    db.localOrders = [_order('so1')];
    expect(repo.getLocalOrders(), db.localOrders);

    final order = _order('so2');
    await repo.saveLocalOrder(order);
    expect(db.savedLocal, order);
  });

  group('enqueueSalesOrder', () {
    test('a create enqueues type sales_order using the local id', () async {
      await repo.enqueueSalesOrder(_order('temp_so_1'), isUpdate: false);
      expect(db.enqueued?.type, 'sales_order');
      expect(db.enqueued?.payload['salesorder_id'], 'temp_so_1');
    });

    test('an update enqueues type update_sales_order with the zoho id stamped', () async {
      await repo.enqueueSalesOrder(
        _order('so1', zohoOrderId: 'zoho_1'),
        isUpdate: true,
      );
      expect(db.enqueued?.type, 'update_sales_order');
      expect(db.enqueued?.payload['salesorder_id'], 'zoho_1');
    });
  });

  test('fetchRemoteOrders maps headers, stamps the van location, and saves to the local cache', () async {
    db.assignedWarehouse = 'van_1';
    api.headersResponse = [
      {
        'salesorder_id': 'zoho_so1',
        'salesorder_number': 'SO-1',
        'customer_id': 'c1',
        'customer_name': 'Cust',
        'date': '2026-08-16',
      },
    ];
    final result = await repo.fetchRemoteOrders();
    expect(db.savedRemote.single.locationId, 'van_1');
    expect(result.single.zohoOrderId, 'zoho_so1');
  });

  group('fetchRemoteOrder', () {
    test('returns the merged local cache entry after a successful fetch', () async {
      api.detailResponse = {
        'salesorder_id': 'zoho_so1',
        'salesorder_number': 'SO-1',
        'customer_id': 'c1',
        'customer_name': 'Cust',
        'date': '2026-08-16',
      };
      final result = await repo.fetchRemoteOrder('zoho_so1');
      expect(result?.zohoOrderId, 'zoho_so1');
      expect(db.savedRemote.single.zohoOrderId, 'zoho_so1');
    });

    test('offline fallback returns the matching local order when the fetch fails', () async {
      db.localOrders = [_order('so1', zohoOrderId: 'zoho_so1')];
      api.throwOnDetail = true;
      final result = await repo.fetchRemoteOrder(
        'zoho_so1',
        allowOfflineFallback: true,
      );
      expect(result?.id, 'so1');
    });
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'so1',
      type: 'convert_so',
      payload: const {},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });
}
