import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_bloc.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_event.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_state.dart';

class FakeSalesRepository
    with CustomerRepositorySubmitStubs
    implements CustomerRepository {
  String? lastCustomerId;
  double? lastLatitude;
  double? lastLongitude;
  String? lastRemoteCustomerId;
  double? lastRemoteLatitude;
  double? lastRemoteLongitude;
  bool shouldThrowRemoteGps = false;
  List<SyncQueueItem> queue = [];

  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {
    lastCustomerId = customerId;
    lastLatitude = latitude;
    lastLongitude = longitude;
  }

  @override
  Future<void> pushCustomerGpsRemote(
    String customerId,
    double latitude,
    double longitude,
  ) async {
    if (shouldThrowRemoteGps) {
      throw Exception('Remote GPS push failed');
    }
    lastRemoteCustomerId = customerId;
    lastRemoteLatitude = latitude;
    lastRemoteLongitude = longitude;
  }

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
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(Customer customer) async =>
      (customer: customer, offlineFallback: false);
  @override
  Future<CustomerLedger> fetchCustomerLedger(
    String customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) => throw UnimplementedError();
  @override
  Customer? getCustomerById(String id) => null;
}

class FakeSyncRepository implements SyncRepository {
  int syncCount = 0;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    syncCount++;
  }

  @override
  Stream<String> get syncStatusStream => const Stream<Never>.empty();
  @override
  Stream<int> get syncCountStream => const Stream<Never>.empty();
  @override
  bool get isSyncing => false;
  @override
  List<SyncQueueItem> getSyncQueue() => [];
  @override
  Future<void> clearFailedSyncItems() async {}
  @override
  int getMasterRecordCount(MasterType type) => 0;
  @override
  bool hasCoreMasters() => true;
  @override
  Future<void> refreshMasterData() async {}
  @override
  Future<void> syncMaster(MasterType type) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late GpsCaptureBloc bloc;

  final testCustomer = const Customer(
    id: 'cust_01',
    name: 'Customer A',
    companyName: 'Company A',
    email: '',
    phone: '',
    address: '',
    outstandingBalance: 0,
    creditLimit: 2000,
    routeId: 'route_01',
    sequence: 1,
  );

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = GpsCaptureBloc(
      customerRepository: salesRepo,
      syncRepository: syncRepo,
    );

    // Setup Method Channel Mock for geolocator and permission_handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isLocationServiceEnabled') {
          return true;
        }
        if (methodCall.method == 'getCurrentPosition') {
          return {
            'latitude': 12.3456,
            'longitude': 78.9012,
            'timestamp': 0,
            'accuracy': 1.0,
            'altitude': 1.0,
            'heading': 1.0,
            'speed': 1.0,
            'speed_accuracy': 1.0,
            'floor': null,
            'is_mocked': false,
          };
        }
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermissionStatus') {
          return 1; // PermissionStatus.granted
        }
        if (methodCall.method == 'requestPermissions') {
          final permissions = methodCall.arguments as List<dynamic>;
          return {
            for (final p in permissions) p: 1, // granted
          };
        }
        return null;
      },
    );
  });

  tearDown(() {
    bloc.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'), null);
  });

  test('GpsCaptureRequested in capture-only mode emits success with lat/lng', () async {
    final future = bloc.stream.firstWhere((state) => state is GpsCaptureSuccess);
    bloc.add(const GpsCaptureRequested(persist: false));
    final state = await future as GpsCaptureSuccess;

    expect(state.latitude, 12.3456);
    expect(state.longitude, 78.9012);
    expect(state.enrichedCustomer, isNull);

    // Should not persist locally
    expect(salesRepo.lastCustomerId, isNull);
  });

  test('GpsCaptureRequested in persist mode updates local and Zoho APIs successfully', () async {
    final future = bloc.stream.firstWhere((state) => state is GpsCaptureSuccess);
    bloc.add(GpsCaptureRequested(customer: testCustomer, persist: true));
    final state = await future as GpsCaptureSuccess;

    expect(state.latitude, 12.3456);
    expect(state.longitude, 78.9012);
    expect(state.enrichedCustomer!.latitude, 12.3456);
    expect(state.enrichedCustomer!.longitude, 78.9012);

    expect(salesRepo.queue, hasLength(1));
    expect(salesRepo.queue.first.type, 'customer_gps_update');
    expect(salesRepo.lastRemoteCustomerId, isNull);
  });

  test('GpsCaptureRequested in persist mode enqueues sync item if Zoho API throws', () async {
    salesRepo.shouldThrowRemoteGps = true;

    final future = bloc.stream.firstWhere((state) => state is GpsCaptureSuccess);
    bloc.add(GpsCaptureRequested(customer: testCustomer, persist: true));
    final state = await future as GpsCaptureSuccess;

    expect(state.latitude, 12.3456);

    expect(salesRepo.lastRemoteCustomerId, isNull);
    expect(salesRepo.queue.length, 1);
    expect(salesRepo.queue.first.type, 'customer_gps_update');
    expect(salesRepo.queue.first.payload['contact_id'], 'cust_01');
  });

  test('GpsCaptureRequested in persist mode enqueues sync item for temp_ customer automatically', () async {
    final tempCustomer = testCustomer.copyWith(id: 'temp_cust_123');

    final future = bloc.stream.firstWhere((state) => state is GpsCaptureSuccess);
    bloc.add(GpsCaptureRequested(customer: tempCustomer, persist: true));
    final state = await future as GpsCaptureSuccess;

    expect(state.latitude, 12.3456);

    expect(salesRepo.lastRemoteCustomerId, isNull);
    expect(salesRepo.queue.length, 1);
    expect(salesRepo.queue.first.payload['contact_id'], 'temp_cust_123');
  });

  test('GpsCaptureRequested rejects an inaccurate fix without persisting', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'isLocationServiceEnabled') {
          return true;
        }
        if (methodCall.method == 'getCurrentPosition') {
          return {
            'latitude': 12.3456,
            'longitude': 78.9012,
            'timestamp': 0,
            'accuracy': 250.0,
            'altitude': 1.0,
            'heading': 1.0,
            'speed': 1.0,
            'speed_accuracy': 1.0,
            'floor': null,
            'is_mocked': false,
          };
        }
        return null;
      },
    );

    final future = bloc.stream.firstWhere((state) => state is GpsCaptureInaccurate);
    bloc.add(GpsCaptureRequested(customer: testCustomer, persist: true));
    final state = await future as GpsCaptureInaccurate;

    expect(state.accuracy, 250.0);
    expect(salesRepo.queue, isEmpty);
  });

  test('ContactFieldsSaveRequested persists phone and TRN', () async {
    final future =
        bloc.stream.firstWhere((state) => state is ContactFieldsSaved);
    bloc.add(ContactFieldsSaveRequested(
      customer: testCustomer,
      phone: '0501234567',
      trn: '100533986400003',
    ));
    final state = await future as ContactFieldsSaved;

    expect(state.enrichedCustomer.phone, '0501234567');
    expect(state.enrichedCustomer.trn, '100533986400003');
    expect(salesRepo.queue, hasLength(1));
    expect(salesRepo.queue.first.type, 'customer_contact_update');
    expect(salesRepo.queue.first.payload['phone'], '0501234567');
    expect(salesRepo.queue.first.payload['tax_reg_no'], '100533986400003');
  });
}
