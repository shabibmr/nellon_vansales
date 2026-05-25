import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';

class FakeHiveDatabaseService extends HiveDatabaseService {
  final List<dynamic> savedData = [];

  @override
  String? get assignedWarehouseId => 'van_wh_01';

  @override
  String? get activeRouteId => null;

  @override
  Future<void> saveOrganization(dynamic org) async {
    savedData.add(org);
  }

  @override
  Future<void> saveWarehouses(dynamic warehouses) async {
    savedData.add(warehouses);
  }

  @override
  Future<void> savePaymentAccounts(dynamic accounts) async {
    savedData.add(accounts);
  }

  @override
  Future<void> saveTaxes(dynamic taxes) async {
    savedData.add(taxes);
  }

  @override
  Future<void> saveExpenseAccounts(dynamic accounts) async {
    savedData.add(accounts);
  }

  @override
  Future<void> saveRoutes(dynamic routes) async {
    savedData.add(routes);
  }

  @override
  Future<void> saveItems(dynamic items) async {
    savedData.add(items);
  }

  @override
  Future<void> saveOpenInvoices(dynamic invoices) async {
    savedData.add(invoices);
  }

  @override
  Future<void> saveCustomers(dynamic customers) async {
    savedData.add(customers);
  }
}

class FakeZohoApiClient extends ZohoApiClient {
  FakeZohoApiClient() : super(dbService: FakeHiveDatabaseService());

  final Map<String, int> callCounts = {};

  @override
  Future<Map<String, dynamic>?> fetchOrganization() async {
    callCounts['fetchOrganization'] = (callCounts['fetchOrganization'] ?? 0) + 1;
    return {
      'organization_id': '783019958',
      'name': 'Test Org',
      'currency_code': 'INR',
      'currency_symbol': '₹',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchWarehouses() async {
    callCounts['fetchWarehouses'] = (callCounts['fetchWarehouses'] ?? 0) + 1;
    return [
      {'warehouse_id': 'wh_01', 'warehouse_name': 'Van 1'}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentAccounts() async {
    callCounts['fetchPaymentAccounts'] = (callCounts['fetchPaymentAccounts'] ?? 0) + 1;
    return [
      {'account_id': 'acc_01', 'account_name': 'Petty Cash'}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTaxes() async {
    callCounts['fetchTaxes'] = (callCounts['fetchTaxes'] ?? 0) + 1;
    return [
      {'tax_id': 'tax_01', 'tax_name': 'GST 5%', 'tax_percentage': 5.0}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchExpenseAccounts() async {
    callCounts['fetchExpenseAccounts'] = (callCounts['fetchExpenseAccounts'] ?? 0) + 1;
    return [
      {'account_id': 'exp_01', 'account_name': 'Fuel'}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoutes() async {
    callCounts['fetchRoutes'] = (callCounts['fetchRoutes'] ?? 0) + 1;
    return [
      {'id': 'route_01', 'name': 'Route A', 'description': 'Downtown'}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    callCounts['fetchItems'] = (callCounts['fetchItems'] ?? 0) + 1;
    return [
      {'item_id': 'item_01', 'name': 'Milk', 'rate': 10.0, 'stock_on_hand': 100}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    callCounts['fetchCustomers'] = (callCounts['fetchCustomers'] ?? 0) + 1;
    return [
      {'contact_id': 'cust_01', 'contact_name': 'Acme Corp'}
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOpenInvoices() async {
    callCounts['fetchOpenInvoices'] = (callCounts['fetchOpenInvoices'] ?? 0) + 1;
    return [
      {'invoice_id': 'inv_01', 'total': 100.0, 'balance': 100.0}
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SyncWorker refreshMasterData (Sync All) executes and caches all master modules successfully', () async {
    final fakeDb = FakeHiveDatabaseService();
    final fakeApi = FakeZohoApiClient();
    final worker = SyncWorker(dbService: fakeDb, apiClient: fakeApi);

    await worker.refreshMasterData();

    // Verify all core fetch API methods were invoked
    expect(fakeApi.callCounts['fetchOrganization'], 1);
    expect(fakeApi.callCounts['fetchWarehouses'], 1);
    expect(fakeApi.callCounts['fetchPaymentAccounts'], 1);
    expect(fakeApi.callCounts['fetchTaxes'], 1);
    expect(fakeApi.callCounts['fetchExpenseAccounts'], 1);
    expect(fakeApi.callCounts['fetchRoutes'], 1);
    expect(fakeApi.callCounts['fetchItems'], 1);
    expect(fakeApi.callCounts['fetchCustomers'], 1);
    expect(fakeApi.callCounts['fetchOpenInvoices'], 1);

    // Verify all 9 categories of master data successfully saved locally
    expect(fakeDb.savedData.length, 9);
  });

  test('SyncWorker syncMaster propagates exceptions and broadcasts error status when API fails', () async {
    final fakeDb = FakeHiveDatabaseService();
    final fakeApi = FakeFailingZohoApiClient();
    final worker = SyncWorker(dbService: fakeDb, apiClient: fakeApi);

    final List<String> statusLogs = [];
    final subscription = worker.syncStatusStream.listen((status) {
      statusLogs.add(status);
    });

    expect(() => worker.syncMaster(MasterType.items), throwsException);

    await Future.delayed(Duration.zero);
    await subscription.cancel();

    expect(statusLogs, contains('Syncing Items...'));
    expect(statusLogs.any((log) => log.contains('Items sync failed: Exception: API Connection timeout')), isTrue);
  });
}

class FakeFailingZohoApiClient extends ZohoApiClient {
  FakeFailingZohoApiClient() : super(dbService: FakeHiveDatabaseService());

  @override
  Future<List<Map<String, dynamic>>> fetchItems(String warehouseId) async {
    throw Exception('API Connection timeout');
  }
}
