import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/session_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/ui/features/dashboard/cubit/create_customer_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/create_customer_state.dart';

class FakeCustomerRepository implements CustomerRepository {
  List<Customer> customers = [];
  List<SyncQueueItem> queue = [];
  bool shouldThrow = false;

  @override
  List<Customer> getCustomers() => customers;

  @override
  Future<void> saveCustomers(List<Customer> customers) async {
    if (shouldThrow) throw Exception('Database error');
    this.customers = customers;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {}
  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {}
  @override
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  }) async {}

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(Customer customer) async => (customer: customer, offlineFallback: false);
  @override
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) => throw UnimplementedError();
  @override
  Customer? getCustomerById(String id) => null;
  @override
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  ) => throw UnimplementedError();
}

class FakeSessionRepository implements SessionRepository {
  @override
  List<RouteModel> getRoutes() => [];
  @override
  String? get activeRouteId => null;
  @override
  Future<void> setActiveRouteId(String? routeId) async {}
  @override
  Organization? getOrganization() => null;
}

class FakeSyncRepository implements SyncRepository {
  bool syncTriggered = false;
  int triggerCount = 0;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    syncTriggered = true;
    triggerCount++;
  }

  @override
  Stream<String> get syncStatusStream => const Stream.empty();
  @override
  Stream<int> get syncCountStream => const Stream.empty();
  @override
  bool get isSyncing => false;
  @override
  List<SyncQueueItem> getSyncQueue() => [];
  @override
  Future<void> clearFailedSyncItems() async {}
  @override
  Future<void> refreshMasterData() async {}
  @override
  Future<void> syncMaster(MasterType type) async {}
  @override
  bool hasCoreMasters() => true;
  @override
  int getMasterRecordCount(MasterType type) => 0;
}

void main() {
  late FakeCustomerRepository customerRepo;
  late FakeSessionRepository sessionRepo;
  late FakeSyncRepository syncRepo;
  late CreateCustomerCubit cubit;

  setUp(() {
    customerRepo = FakeCustomerRepository();
    sessionRepo = FakeSessionRepository();
    syncRepo = FakeSyncRepository();
    cubit = CreateCustomerCubit(
      customerRepository: customerRepo,
      sessionRepository: sessionRepo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() {
    cubit.close();
  });

  test('Initial state is CreateCustomerInitial', () {
    expect(cubit.state, CreateCustomerInitial());
  });

  test('submit successfully saves customer locally and queues Zoho sync item', () async {
    final future = cubit.stream.firstWhere((state) => state is CreateCustomerSuccess);

    await cubit.submit(
      name: 'John Doe',
      company: 'John Shop',
      email: 'john@example.com',
      phone: '1234567890',
      address: '123 St',
      creditLimit: 1500.0,
      activeRouteId: 'route_123',
      latitude: 12.34,
      longitude: 56.78,
    );

    final state = await future as CreateCustomerSuccess;
    expect(state.customer.name, 'John Doe');
    expect(state.customer.companyName, 'John Shop');
    expect(state.customer.routeId, 'route_123');
    expect(state.customer.latitude, 12.34);
    expect(state.customer.longitude, 56.78);
    expect(state.customer.isPendingSync, true);

    // Verify local storage
    expect(customerRepo.customers.length, 1);
    expect(customerRepo.customers.first.name, 'John Doe');

    // Verify sync queue payload
    expect(customerRepo.queue.length, 1);
    final syncItem = customerRepo.queue.first;
    expect(syncItem.type, 'customer');
    expect(syncItem.payload['contact_name'], 'John Doe');
    expect(syncItem.payload['credit_limit'], 1500.0);
    final customFields = syncItem.payload['custom_fields'] as List;
    expect(customFields[0]['api_name'], 'cf_latitude');
    expect(customFields[0]['value'], '12.34');
  });

  test('submit failure path emits CreateCustomerFailure state', () async {
    customerRepo.shouldThrow = true;
    final future = cubit.stream.firstWhere((state) => state is CreateCustomerFailure);

    await cubit.submit(
      name: 'John Doe',
      company: 'John Shop',
      email: 'john@example.com',
      phone: '1234567890',
      address: '123 St',
      creditLimit: 1500.0,
      activeRouteId: 'route_123',
    );

    final state = await future as CreateCustomerFailure;
    expect(state.message, contains('Database error'));
    expect(customerRepo.queue.isEmpty, true);
  });
}
