import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/customer_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/customer.dart';

class _FakeDb extends HiveDatabaseService {
  final Map<String, ({String trn, String address})> details = {};
  final List<Customer> customers = [];

  @override
  bool hasCustomerDetail(String id) => details.containsKey(id);

  @override
  ({String trn, String address})? getCustomerDetail(String id) => details[id];

  @override
  Future<void> saveCustomerDetail(
    String id, {
    required String trn,
    required String address,
  }) async {
    details[id] = (trn: trn, address: address);
  }

  @override
  Future<void> upsertCustomer(Customer customer) async {
    final index = customers.indexWhere((c) => c.id == customer.id);
    if (index >= 0) {
      customers[index] = customer;
    } else {
      customers.add(customer);
    }
  }

  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    final index = customers.indexWhere((c) => c.id == customerId);
    if (index < 0) return;
    customers[index] = customers[index].copyWith(
      phone: phone ?? customers[index].phone,
      trn: trn ?? customers[index].trn,
    );
    if (trn != null) {
      details[customerId] = (
        trn: trn,
        address: details[customerId]?.address ?? customers[index].address,
      );
    }
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(_FakeDb db) : super(dbService: db);

  final List<String> detailCalls = [];
  bool throwOnFetch = false;
  String? lastUpdatedId;
  String? lastPhone;
  String? lastTrn;
  bool throwOnUpdate = false;

  @override
  Future<Map<String, dynamic>> fetchContactDetail(String contactId) async {
    detailCalls.add(contactId);
    if (throwOnFetch) throw Exception('offline');
    if (contactId == 'unregistered') {
      return {
        'contact_id': contactId,
        'contact_name': 'No TRN Shop',
        'tax_reg_no': '',
        'billing_address': {'address': ''},
      };
    }
    return {
      'contact_id': contactId,
      'contact_name': 'AL AMANAH',
      'tax_reg_no': '100533986400003',
      'vat_reg_no': '100533986400003',
      'billing_address': {'address': 'NEAR FIRE STATION ROAD MUWAILAH'},
    };
  }

  @override
  Future<String> updateCustomerContactFields(
    String contactId, {
    String? phone,
    String? trn,
  }) async {
    if (throwOnUpdate) throw Exception('offline');
    lastUpdatedId = contactId;
    lastPhone = phone;
    lastTrn = trn;
    return contactId;
  }
}

Customer _customer(String id, {String trn = '', String address = ''}) =>
    Customer(
      id: id,
      name: id,
      companyName: id,
      email: '',
      phone: '',
      address: address,
      trn: trn,
      outstandingBalance: 0,
      creditLimit: 0,
      routeId: 'r1',
      sequence: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDb db;
  late _FakeApi api;
  late CustomerRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = CustomerRepositoryImpl(dbService: db, apiClient: api);
  });

  test('non-empty TRN skips the network', () async {
    final resolved = await repo.resolveCustomerDetails(
      _customer('c1', trn: '100111'),
    );
    expect(api.detailCalls, isEmpty);
    expect(resolved.offlineFallback, isFalse);
    expect(resolved.customer.trn, '100111');
  });

  test('temp_ id skips the network', () async {
    final resolved = await repo.resolveCustomerDetails(_customer('temp_cust_1'));
    expect(api.detailCalls, isEmpty);
    expect(resolved.customer.trn, isEmpty);
  });

  test('first tap fetches contact detail and caches TRN', () async {
    final resolved = await repo.resolveCustomerDetails(_customer('amanah'));
    expect(api.detailCalls, ['amanah']);
    expect(resolved.offlineFallback, isFalse);
    expect(resolved.customer.trn, '100533986400003');
    expect(resolved.customer.address, 'NEAR FIRE STATION ROAD MUWAILAH');
    expect(db.hasCustomerDetail('amanah'), isTrue);
  });

  test('second tap of the same customer does not fetch', () async {
    await repo.resolveCustomerDetails(_customer('amanah'));
    final again = await repo.resolveCustomerDetails(_customer('amanah'));
    expect(api.detailCalls, ['amanah']);
    expect(again.customer.trn, '100533986400003');
  });

  test('empty TRN is cached so unregistered customers are not refetched',
      () async {
    final first = await repo.resolveCustomerDetails(_customer('unregistered'));
    final second = await repo.resolveCustomerDetails(_customer('unregistered'));
    expect(first.customer.trn, isEmpty);
    expect(second.customer.trn, isEmpty);
    expect(api.detailCalls, ['unregistered']);
    expect(db.getCustomerDetail('unregistered')?.trn, isEmpty);
  });

  test('fetch failure does not cache and retries next tap', () async {
    api.throwOnFetch = true;
    final failed = await repo.resolveCustomerDetails(_customer('amanah'));
    expect(failed.offlineFallback, isTrue);
    expect(db.hasCustomerDetail('amanah'), isFalse);

    api.throwOnFetch = false;
    final retried = await repo.resolveCustomerDetails(_customer('amanah'));
    expect(api.detailCalls, ['amanah', 'amanah']);
    expect(retried.offlineFallback, isFalse);
    expect(retried.customer.trn, '100533986400003');
  });

  test('updateCustomerContactFields writes phone, TRN and TRN cache',
      () async {
    db.customers.add(_customer('amanah'));
    await repo.updateCustomerContactFields(
      'amanah',
      phone: '0501234567',
      trn: '100533986400003',
    );
    expect(db.customers.single.phone, '0501234567');
    expect(db.customers.single.trn, '100533986400003');
    expect(db.getCustomerDetail('amanah')?.trn, '100533986400003');
  });

  test('pushCustomerContactFieldsRemote sends phone and tax_reg_no', () async {
    await repo.pushCustomerContactFieldsRemote(
      'amanah',
      phone: '0501234567',
      trn: '100533986400003',
    );
    expect(api.lastUpdatedId, 'amanah');
    expect(api.lastPhone, '0501234567');
    expect(api.lastTrn, '100533986400003');
  });
}
