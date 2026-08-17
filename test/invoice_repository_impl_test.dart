import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/invoice_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';

class _FakeDb extends HiveDatabaseService {
  List<SalesInvoice> localInvoices = [];
  List<SalesInvoice> savedRemote = [];
  SalesInvoice? savedLocal;
  SyncQueueItem? enqueued;
  String? assignedWarehouse;

  @override
  List<SalesInvoice> getLocalInvoices() => localInvoices;

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    savedLocal = invoice;
  }

  @override
  Future<void> saveRemoteInvoices(List<SalesInvoice> remote) async {
    savedRemote = remote;
    localInvoices = remote;
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
    : super(dbService: db);

  bool throwOnDetail = false;
  Map<String, dynamic> detailResponse = {};
  List<Map<String, dynamic>> headersResponse = [];

  @override
  Future<Map<String, dynamic>> fetchInvoiceDetail(String invoiceId) async {
    if (throwOnDetail) throw Exception('offline');
    return detailResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchInvoiceHeaders({
    DateTime? startDate,
    DateTime? endDate,
  }) async => headersResponse;
}

SalesInvoice _invoice(String id) => SalesInvoice(
  id: id,
  invoiceNumber: 'INV-1',
  customerId: 'c1',
  customerName: 'Cust',
  date: DateTime(2026, 8, 16),
  dueDate: DateTime(2026, 8, 23),
  items: const [],
  notes: '',
);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late InvoiceRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = InvoiceRepositoryImpl(dbService: db, apiClient: api);
  });

  test('getLocalInvoices / saveLocalInvoice delegate to dbService', () async {
    db.localInvoices = [_invoice('inv1')];
    expect(repo.getLocalInvoices(), db.localInvoices);

    final invoice = _invoice('inv2');
    await repo.saveLocalInvoice(invoice);
    expect(db.savedLocal, invoice);
  });

  group('fetchInvoiceById', () {
    test('returns local copy without hitting the network when not forcing remote', () async {
      db.localInvoices = [_invoice('inv1')];
      final result = await repo.fetchInvoiceById('inv1');
      expect(result?.id, 'inv1');
    });

    test('force-remote fetch maps and caches the Zoho response', () async {
      api.detailResponse = {
        'invoice_id': 'inv1',
        'customer_id': 'c1',
        'customer_name': 'Cust',
        'date': '2026-08-16',
        'due_date': '2026-08-23',
        'line_items': <dynamic>[],
      };
      final result = await repo.fetchInvoiceById('inv1', forceRemote: true);
      expect(result?.id, 'inv1');
      expect(db.savedRemote.single.id, 'inv1');
    });

    test('offline fallback returns local copy when the remote call fails', () async {
      db.localInvoices = [_invoice('inv1')];
      api.throwOnDetail = true;
      final result = await repo.fetchInvoiceById('inv1', forceRemote: true);
      expect(result?.id, 'inv1');
    });

    test('rethrows when the remote call fails and no offline fallback is allowed', () async {
      api.throwOnDetail = true;
      await expectLater(
        repo.fetchInvoiceById('inv1', forceRemote: true, allowOfflineFallback: false),
        throwsException,
      );
    });
  });

  test('fetchRemoteInvoices maps headers, stamps the van location, and saves to the local cache', () async {
    db.assignedWarehouse = 'van_1';
    api.headersResponse = [
      {
        'invoice_id': 'inv1',
        'customer_id': 'c1',
        'customer_name': 'Cust',
        'date': '2026-08-16',
        'due_date': '2026-08-23',
      },
    ];
    final result = await repo.fetchRemoteInvoices();
    expect(db.savedRemote.single.locationId, 'van_1');
    expect(result.single.id, 'inv1');
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'inv1',
      type: 'invoice',
      payload: const <String, dynamic>{},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });
}
