import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/sync_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';

class _FakeDb extends HiveDatabaseService {
  final Map<String, dynamic> store = {};

  @override
  int countMasterList(String key) {
    final raw = store[key];
    return raw is List ? raw.length : 0;
  }

  @override
  bool hasMasterValue(String key) => store.containsKey(key);
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(_FakeDb db) : super(dbService: db);
}

void main() {
  late _FakeDb db;
  late SyncRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    repo = SyncRepositoryImpl(
      syncWorker: SyncWorker(
        dbService: db,
        apiClient: _FakeApi(db),
        checkConnectivity: () async => const [],
      ),
      dbService: db,
    );
  });

  test('organization counts as 0 or 1 based on Hive presence', () {
    expect(repo.getMasterRecordCount(MasterType.organization), 0);
    db.store['organization'] = '{"name":"Nellon"}';
    expect(repo.getMasterRecordCount(MasterType.organization), 1);
  });

  test('list masters count raw Hive entries without deserializing', () {
    db.store['customers'] = ['a', 'b', 'c'];
    db.store['items'] = ['i1'];
    db.store['warehouses'] = <dynamic>[];

    expect(repo.getMasterRecordCount(MasterType.customers), 3);
    expect(repo.getMasterRecordCount(MasterType.items), 1);
    expect(repo.getMasterRecordCount(MasterType.warehouses), 0);
    expect(repo.getMasterRecordCount(MasterType.routes), 0);
  });

  test('maps every MasterType to its Hive key', () {
    db.store['organization'] = '{}';
    db.store['warehouses'] = ['w'];
    db.store['payment_accounts'] = ['p1', 'p2'];
    db.store['taxes'] = ['t'];
    db.store['expense_accounts'] = ['e1', 'e2', 'e3'];
    db.store['routes'] = ['r1', 'r2'];
    db.store['items'] = ['i1', 'i2', 'i3', 'i4'];
    db.store['customers'] = ['c1'];
    db.store['salespersons'] = ['s1', 's2'];

    expect(repo.getMasterRecordCount(MasterType.organization), 1);
    expect(repo.getMasterRecordCount(MasterType.warehouses), 1);
    expect(repo.getMasterRecordCount(MasterType.paymentAccounts), 2);
    expect(repo.getMasterRecordCount(MasterType.taxes), 1);
    expect(repo.getMasterRecordCount(MasterType.expenseAccounts), 3);
    expect(repo.getMasterRecordCount(MasterType.routes), 2);
    expect(repo.getMasterRecordCount(MasterType.items), 4);
    expect(repo.getMasterRecordCount(MasterType.customers), 1);
    expect(repo.getMasterRecordCount(MasterType.salespersons), 2);
  });
}
