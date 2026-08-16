import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/sales_return_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_return.dart';

class _FakeDb extends HiveDatabaseService {
  List<SalesReturn> localReturns = [];
  List<SalesReturn> savedRemote = [];
  SalesReturn? savedLocal;
  SyncQueueItem? enqueued;
  String? assignedWarehouse;

  @override
  List<SalesReturn> getLocalReturns() => localReturns;

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    savedLocal = salesReturn;
  }

  @override
  Future<void> saveRemoteReturns(List<SalesReturn> remote) async {
    savedRemote = remote;
    localReturns = remote;
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
  Future<Map<String, dynamic>> fetchSalesReturnDetail(
    String creditNoteId,
  ) async {
    if (throwOnDetail) throw Exception('offline');
    return detailResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSalesReturnHeaders({
    DateTime? startDate,
    DateTime? endDate,
  }) async => headersResponse;
}

const _item = Item(
  id: 'item_1',
  name: 'Item One',
  sku: 'SKU1',
  rate: 10.0,
  stock: 10,
  description: '',
  taxName: 'No Tax',
  taxPercentage: 0.0,
);

SalesReturn _salesReturn(String id) => SalesReturn(
  id: id,
  creditNoteNumber: 'CN-1',
  customerId: 'c1',
  customerName: 'Cust',
  date: DateTime(2026, 8, 16),
  items: [
    SalesReturnLineItem(
      invoiceLineItem: InvoiceLineItem(
        item: _item,
        quantity: 2,
        rate: 10,
        taxPercentage: 0,
      ),
      returnedQuantity: 1,
    ),
  ],
  reason: 'Damaged',
);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late SalesReturnRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = SalesReturnRepositoryImpl(dbService: db, apiClient: api);
  });

  test('getLocalReturns / saveLocalReturn delegate to dbService', () async {
    db.localReturns = [_salesReturn('sr1')];
    expect(repo.getLocalReturns(), db.localReturns);

    final salesReturn = _salesReturn('sr2');
    await repo.saveLocalReturn(salesReturn);
    expect(db.savedLocal, salesReturn);
  });

  group('fetchSalesReturnById', () {
    test('returns local copy without hitting the network when not forcing remote', () async {
      db.localReturns = [_salesReturn('sr1')];
      final result = await repo.fetchSalesReturnById('sr1');
      expect(result?.id, 'sr1');
    });

    test('offline fallback returns local copy when the remote call fails', () async {
      db.localReturns = [_salesReturn('sr1')];
      api.throwOnDetail = true;
      final result = await repo.fetchSalesReturnById('sr1', forceRemote: true);
      expect(result?.id, 'sr1');
    });

    test('rethrows when the remote call fails and no offline fallback is allowed', () async {
      api.throwOnDetail = true;
      await expectLater(
        repo.fetchSalesReturnById(
          'sr1',
          forceRemote: true,
          allowOfflineFallback: false,
        ),
        throwsException,
      );
    });
  });

  test('fetchRemoteReturns maps headers, stamps the van location, and saves to the local cache', () async {
    db.assignedWarehouse = 'van_1';
    api.headersResponse = [
      {
        'creditnote_id': 'sr1',
        'customer_id': 'c1',
        'customer_name': 'Cust',
        'date': '2026-08-16',
        'total': 30,
      },
    ];
    final result = await repo.fetchRemoteReturns();
    expect(db.savedRemote.single.locationId, 'van_1');
    expect(result.single.id, 'sr1');
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'sr1',
      type: 'return',
      payload: const {},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });
}
