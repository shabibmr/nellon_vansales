import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/receipt_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';

class _FakeDb extends HiveDatabaseService {
  List<ReceiptVoucher> localReceipts = [];
  List<ReceiptVoucher> savedRemote = [];
  ReceiptVoucher? savedLocal;
  List<OpenInvoice> openInvoices = [];
  List<OpenInvoice> savedOpenInvoices = [];
  SyncQueueItem? enqueued;
  String? assignedWarehouse;
  String? prefix;

  @override
  List<ReceiptVoucher> getLocalReceipts() => localReceipts;

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    savedLocal = voucher;
  }

  @override
  Future<void> saveRemoteReceipts(List<ReceiptVoucher> remote) async {
    savedRemote = remote;
    localReceipts = remote;
  }

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) {
    if (customerId == null) return openInvoices;
    return openInvoices.where((i) => i.customerId == customerId).toList();
  }

  @override
  Future<void> saveOpenInvoices(List<OpenInvoice> invoices) async {
    savedOpenInvoices = invoices;
  }

  @override
  String? get assignedWarehouseId => assignedWarehouse;

  @override
  String? get voucherPrefix => prefix;

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
  List<Map<String, dynamic>> receiptsResponse = [];
  List<Map<String, dynamic>> openInvoicesResponse = [];

  @override
  Future<Map<String, dynamic>> fetchReceiptDetail(String paymentId) async {
    if (throwOnDetail) throw Exception('offline');
    return detailResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => receiptsResponse;

  @override
  Future<List<Map<String, dynamic>>> fetchOpenInvoices({
    String? customerId,
  }) async => openInvoicesResponse;
}

ReceiptVoucher _receipt(String id, {String customerId = 'c1', String paymentNumber = 'PAY-1'}) =>
    ReceiptVoucher(
      id: id,
      paymentNumber: paymentNumber,
      customerId: customerId,
      customerName: 'Cust',
      allocations: const [],
      amount: 100,
      paymentMode: 'Cash',
      referenceNumber: '',
      date: DateTime(2026, 8, 16),
    );

OpenInvoice _openInvoice(String id, String customerId) => OpenInvoice(
  invoiceId: id,
  invoiceNumber: 'INV-$id',
  customerId: customerId,
  date: DateTime(2026, 8, 1),
  dueDate: DateTime(2026, 8, 30),
  total: 500,
  balance: 200,
  status: 'unpaid',
);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late ReceiptRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = ReceiptRepositoryImpl(dbService: db, apiClient: api);
  });

  group('getLocalReceipts session scoping', () {
    test('returns everything when no voucher prefix is configured', () {
      db.localReceipts = [
        _receipt('r1', paymentNumber: 'PAY-1'),
        _receipt('r2', paymentNumber: 'SHB-RCT-2'),
      ];
      expect(repo.getLocalReceipts(), hasLength(2));
    });

    test('filters to this session series when a voucher prefix is set', () {
      db.prefix = 'SHB-';
      db.localReceipts = [
        _receipt('r1', paymentNumber: 'PAY-1'),
        _receipt('r2', paymentNumber: 'SHB-RCT-2'),
      ];
      final result = repo.getLocalReceipts();
      expect(result, hasLength(1));
      expect(result.single.id, 'r2');
    });
  });

  test('saveLocalReceipt delegates to dbService', () async {
    final voucher = _receipt('r1');
    await repo.saveLocalReceipt(voucher);
    expect(db.savedLocal, voucher);
  });

  group('fetchReceiptById', () {
    test('returns local copy without hitting the network when not forcing remote', () async {
      db.localReceipts = [_receipt('r1')];
      final result = await repo.fetchReceiptById('r1');
      expect(result?.id, 'r1');
    });

    test('offline fallback returns local copy when the remote call fails', () async {
      db.localReceipts = [_receipt('r1')];
      api.throwOnDetail = true;
      final result = await repo.fetchReceiptById('r1', forceRemote: true);
      expect(result?.id, 'r1');
    });
  });

  test('fetchRemoteReceipts maps, stamps the van location, saves, and re-applies session scoping', () async {
    db.assignedWarehouse = 'van_1';
    db.prefix = 'SHB-';
    api.receiptsResponse = [
      {
        'payment_id': 'r1',
        'customer_id': 'c1',
        'customer_name': 'Cust',
        'amount': 100,
        'reference_number': 'SHB-RCT-1',
        'date': '2026-08-16',
      },
    ];
    final result = await repo.fetchRemoteReceipts();
    expect(db.savedRemote.single.locationId, 'van_1');
    expect(result, hasLength(1));
  });

  group('open invoices', () {
    test('getOpenInvoices delegates to dbService', () {
      db.openInvoices = [_openInvoice('inv1', 'c1')];
      expect(repo.getOpenInvoices(customerId: 'c1'), hasLength(1));
    });

    test('fetchRemoteOpenInvoices for a specific customer merges without wiping others', () async {
      db.openInvoices = [_openInvoice('inv_other', 'c2')];
      api.openInvoicesResponse = [
        {
          'invoice_id': 'inv1',
          'invoice_number': 'INV-1',
          'customer_id': 'c1',
          'total': 500,
          'balance': 200,
        },
      ];
      final result = await repo.fetchRemoteOpenInvoices(customerId: 'c1');
      expect(result, hasLength(1));
      expect(
        db.savedOpenInvoices.map((i) => i.invoiceId),
        containsAll(['inv1', 'inv_other']),
      );
    });

    test('fetchRemoteOpenInvoices with no customer replaces the whole cache', () async {
      db.openInvoices = [_openInvoice('inv_old', 'c9')];
      api.openInvoicesResponse = [
        {'invoice_id': 'inv_new', 'invoice_number': 'INV-N', 'customer_id': 'c1'},
      ];
      await repo.fetchRemoteOpenInvoices();
      expect(db.savedOpenInvoices.map((i) => i.invoiceId), ['inv_new']);
    });
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'r1',
      type: 'receipt',
      payload: const {},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });
}
