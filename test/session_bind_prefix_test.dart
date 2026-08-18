import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/salesperson_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/salesperson.dart';
import 'package:van_sales/domain/models/session_bind_result.dart';
import 'package:van_sales/domain/models/warehouse.dart';

/// Minimal Hive stand-in for bind persistence + salesperson cache.
class _FakeDb extends HiveDatabaseService {
  List<Salesperson> salespersons = [];
  String? sessionPhone;
  String? assignedWarehouseId;
  String? primaryWarehouseId;
  String? cashAccountId;
  String? voucherPrefix;
  bool ordersOnlyMode = false;
  Salesperson? current;

  @override
  List<Salesperson> getSalespersons() => salespersons;

  @override
  Future<void> saveSalespersons(List<Salesperson> list) async {
    salespersons = List.from(list);
  }

  @override
  Future<void> saveWarehouses(List<Warehouse> list) async {}

  @override
  Future<void> setPrimaryWarehouseId(String? id) async {
    primaryWarehouseId = id;
  }

  @override
  Future<void> setSessionPhone(String? phone) async {
    sessionPhone = phone;
  }

  @override
  Future<void> setAssignedWarehouseId(String? id) async {
    assignedWarehouseId = id;
  }

  @override
  Future<void> setOrdersOnlyMode(bool value) async {
    ordersOnlyMode = value;
  }

  @override
  Future<void> setCashAccountId(String? id) async {
    cashAccountId = id;
  }

  @override
  Future<void> setVoucherPrefix(String? prefix) async {
    voucherPrefix = prefix;
  }

  @override
  Future<void> saveCurrentSalesperson(Salesperson sp) async {
    current = sp;
  }
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(_FakeDb db) : super(dbService: db);

  List<Map<String, dynamic>> profiles = [];
  List<Map<String, dynamic>> salespersons = [];
  List<Map<String, dynamic>> warehouses = [
    {
      'location_id': 'loc_primary',
      'location_name': 'KGT',
      'is_primary_location': true,
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchSalespersonProfiles() async =>
      profiles;

  @override
  Future<List<Map<String, dynamic>>> fetchSalespersons() async => salespersons;

  @override
  Future<List<Map<String, dynamic>>> fetchWarehouses() async => warehouses;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDb db;
  late _FakeApi api;
  late SalespersonRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(db);
    repo = SalespersonRepositoryImpl(dbService: db, apiClient: api);

    api.salespersons = [
      {
        'salesperson_id': 'sp1',
        'salesperson_name': 'TEST Agent',
        'status': 'active',
      },
    ];
  });

  Map<String, dynamic> profile({
    String phone = '+971542891246',
    String? prefix = 'SHB-',
    String? van,
  }) {
    return {
      'record_name': phone,
      'cf_active': true,
      'cf_salesperson': 'sp1',
      'cf_salesperson_formatted': 'Test Agent',
      'cf_cash_account': 'cash1',
      'cf_cash_account_formatted': 'Cash In Hand',
      if (prefix != null) 'cf_series_prefix': prefix,
      if (van != null) 'cf_van_location': van,
      if (van != null) 'cf_van_location_formatted': 'Van',
    };
  }

  test('missing series prefix fails as notFullyMapped', () async {
    api.profiles = [profile(prefix: null)];
    final result = await repo.verifyAndBindSession('+971542891246');
    expect(result.isSuccess, isFalse);
    expect(result.failure, SessionBindFailure.notFullyMapped);
    expect(db.current, isNull);
  });

  test('blank series prefix fails as notFullyMapped', () async {
    api.profiles = [profile(prefix: '  ')];
    final result = await repo.verifyAndBindSession('+971542891246');
    expect(result.isSuccess, isFalse);
    expect(result.failure, SessionBindFailure.notFullyMapped);
  });

  test('present series prefix binds successfully', () async {
    api.profiles = [profile(prefix: 'SHB-', van: 'van1')];
    // Seed cache so confirm step finds the salesperson.
    db.salespersons = const [
      Salesperson(
        id: 'sp1',
        name: 'Test Agent',
        email: '',
        status: 'active',
      ),
    ];
    final result = await repo.verifyAndBindSession('+971542891246');
    expect(result.isSuccess, isTrue);
    expect(db.voucherPrefix, 'SHB-');
    expect(db.current?.voucherPrefix, 'SHB-');
  });

  test('matches a draft-status profile by E.164 record_name', () async {
    api.profiles = [
      profile(phone: '+971542891249', prefix: 'SND-', van: 'van1')
        ..['status'] = 'draft',
    ];
    db.salespersons = const [
      Salesperson(
        id: 'sp1',
        name: 'Test Agent',
        email: '',
        status: 'active',
      ),
    ];
    final result = await repo.verifyAndBindSession('+971542891249');
    expect(result.isSuccess, isTrue);
    expect(db.voucherPrefix, 'SND-');
  });
}
