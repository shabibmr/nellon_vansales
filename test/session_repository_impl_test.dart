import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/session_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/route.dart';

class _FakeDb extends HiveDatabaseService {
  List<RouteModel> routes = [];
  String? active;
  String? setRouteId;
  Organization? org;

  @override
  List<RouteModel> getRoutes() => routes;

  @override
  String? get activeRouteId => active;

  @override
  Future<void> setActiveRouteId(String? routeId) async {
    setRouteId = routeId;
    active = routeId;
  }

  @override
  Organization? getOrganization() => org;
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(HiveDatabaseService db)
    : super(dbService: db, mockLatency: Duration.zero);
}

void main() {
  late _FakeDb db;
  late SessionRepositoryImpl repo;

  setUp(() {
    db = _FakeDb();
    repo = SessionRepositoryImpl(dbService: db, apiClient: _FakeApi(db));
  });

  test('getRoutes delegates to dbService', () {
    db.routes = [
      const RouteModel(id: 'r1', name: 'Route 1', description: ''),
    ];
    expect(repo.getRoutes(), db.routes);
  });

  test('activeRouteId reads and setActiveRouteId writes through to dbService', () async {
    db.active = 'r1';
    expect(repo.activeRouteId, 'r1');

    await repo.setActiveRouteId('r2');
    expect(db.setRouteId, 'r2');
    expect(repo.activeRouteId, 'r2');
  });

  test('getOrganization delegates to dbService', () {
    db.org = const Organization(
      id: 'org1',
      name: 'Test Org',
      currencyCode: 'AED',
      currencySymbol: 'AED',
      fiscalYearStartMonth: '1',
      timeZone: 'Asia/Dubai',
    );
    expect(repo.getOrganization()?.id, 'org1');
  });
}
