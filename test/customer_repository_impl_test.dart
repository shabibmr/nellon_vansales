import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/customer_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/customer.dart';

class _FakeDb extends HiveDatabaseService {
  List<Customer> customers = [];
  List<Customer>? savedCustomers;
  String? gpsCustomerId;
  double? gpsLat;
  double? gpsLng;
  SyncQueueItem? enqueued;

  @override
  List<Customer> getCustomers() => customers;

  @override
  Future<void> saveCustomers(List<Customer> customers) async {
    savedCustomers = customers;
  }

  @override
  Customer? getCustomerById(String id) =>
      customers.where((c) => c.id == id).firstOrNull;

  @override
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    gpsCustomerId = customerId;
    gpsLat = latitude;
    gpsLng = longitude;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    enqueued = item;
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db, mockLatency: Duration.zero);

  String? gpsCustomerId;
  double? gpsLat;
  double? gpsLng;
  bool throwOnGps = false;

  Map<String, dynamic> statementResponse = const {};

  @override
  Future<String> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    if (throwOnGps) throw Exception('offline');
    gpsCustomerId = customerId;
    gpsLat = latitude;
    gpsLng = longitude;
    return customerId;
  }

  @override
  Future<Map<String, dynamic>> fetchCustomerStatement(
    String contactId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return statementResponse;
  }
}

Customer _customer(String id, {String name = 'Shop A'}) => Customer(
  id: id,
  name: name,
  companyName: name,
  email: '',
  phone: '',
  address: '',
  outstandingBalance: 0,
  creditLimit: 0,
  routeId: 'r1',
  sequence: 1,
);

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late CustomerRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = CustomerRepositoryImpl(dbService: db, apiClient: api);
  });

  test('getCustomers / saveCustomers / getCustomerById delegate to dbService', () async {
    db.customers = [_customer('c1')];
    expect(repo.getCustomers(), db.customers);

    await repo.saveCustomers([_customer('c2')]);
    expect(db.savedCustomers!.single.id, 'c2');

    expect(repo.getCustomerById('c1')?.id, 'c1');
    expect(repo.getCustomerById('missing'), isNull);
  });

  test('updateCustomerGps delegates to dbService', () async {
    await repo.updateCustomerGps('c1', 25.1, 55.2);
    expect(db.gpsCustomerId, 'c1');
    expect(db.gpsLat, 25.1);
    expect(db.gpsLng, 55.2);
  });

  test('pushCustomerGpsRemote delegates to apiClient and rethrows on failure', () async {
    await repo.pushCustomerGpsRemote('c1', 25.1, 55.2);
    expect(api.gpsCustomerId, 'c1');

    api.throwOnGps = true;
    await expectLater(
      repo.pushCustomerGpsRemote('c1', 25.1, 55.2),
      throwsException,
    );
  });

  test('enqueueSyncItem delegates to dbService', () async {
    final item = SyncQueueItem(
      id: 'c1',
      type: 'customer',
      payload: const {},
      timestamp: DateTime(2026, 8, 16),
    );
    await repo.enqueueSyncItem(item);
    expect(db.enqueued, item);
  });

  group('fetchCustomerLedger', () {
    test('uses the Zoho contact name when present', () async {
      api.statementResponse = {
        'contact_name': 'AL AMANAH',
        'opening_balance': 0,
        'closing_balance': 0,
        'transactions': [],
      };
      final ledger = await repo.fetchCustomerLedger('c1');
      expect(ledger.customerName, 'AL AMANAH');
      expect(ledger.customerId, 'c1');
    });

    test('falls back to the local customer name when Zoho name is blank', () async {
      db.customers = [_customer('c1', name: 'Local Shop')];
      api.statementResponse = {
        'contact_name': '',
        'opening_balance': 0,
        'closing_balance': 0,
        'transactions': [],
      };
      final ledger = await repo.fetchCustomerLedger('c1');
      expect(ledger.customerName, 'Local Shop');
    });

    test('falls back to the local customer name when Zoho returns the demo placeholder', () async {
      db.customers = [_customer('c1', name: 'Local Shop')];
      api.statementResponse = {
        'contact_name': 'Demo Customer',
        'opening_balance': 0,
        'closing_balance': 0,
        'transactions': [],
      };
      final ledger = await repo.fetchCustomerLedger('c1');
      expect(ledger.customerName, 'Local Shop');
    });
  });
}
