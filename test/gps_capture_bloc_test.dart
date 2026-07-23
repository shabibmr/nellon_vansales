import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_bloc.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_event.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_state.dart';

class FakeSalesRepository implements SalesRepository {
  double? lastLatitude;
  double? lastLongitude;
  String? lastCustomerId;
  List<SyncQueueItem> queue = [];

  @override
  Future<void> updateCustomerGps(String customerId, double latitude, double longitude) async {
    lastCustomerId = customerId;
    lastLatitude = latitude;
    lastLongitude = longitude;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  // Stub other methods
  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
  @override
  List<SyncQueueItem> getSyncQueue() => queue;
  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async =>
      [];
  @override
  List<ReceiptVoucher> getLocalReceipts() => [];
  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}
  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  List<RouteModel> getRoutes() => [];
  @override
  String? get activeRouteId => null;
  @override
  Future<void> setActiveRouteId(String? routeId) async {}
  @override
  List<Item> getItems() => [];
  @override
  Future<void> saveItems(List<Item> items) async {}

  @override
  Future<Item> resolveItemUnitConversions(Item item) async => item;
  @override
  List<SalesInvoice> getLocalInvoices() => [];
  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}
  @override
  Future<SalesInvoice?> fetchInvoiceById(String invoiceId) async => null;
  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<ReceiptVoucher?> fetchReceiptById(String paymentId) async => null;
  @override
  Future<SalesReturn?> fetchSalesReturnById(String creditNoteId) async => null;
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;
  @override
  List<SalesReturn> getLocalReturns() => [];
  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}
  @override
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  List<ExpenseEntry> getLocalExpenses() => [];
  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {}
  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
  @override
  CashClosing? getLocalCashClosing() => null;
  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}
  @override
  List<StockTransfer> getLocalStockTransfers() => [];
  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}
  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
}

class FakeZohoApiClient extends ZohoApiClient {
  FakeZohoApiClient({required super.dbService});

  double? lastLatitude;
  double? lastLongitude;
  String? lastCustomerId;
  bool shouldThrow = false;

  @override
  Future<String> updateCustomerGps(String customerId, double latitude, double longitude) async {
    if (shouldThrow) {
      throw Exception('Zoho API failed');
    }
    lastCustomerId = customerId;
    lastLatitude = latitude;
    lastLongitude = longitude;
    return 'success';
  }
}

class FakeHiveDatabaseService extends HiveDatabaseService {
  @override
  String? get assignedWarehouseId => 'van_wh_01';
  @override
  String? get activeRouteId => null;
}

class FakeSyncWorker extends SyncWorker {
  FakeSyncWorker({required super.dbService, required super.apiClient});

  int syncCount = 0;

  @override
  Future<void> syncPendingItems({bool forceRetryAll = false}) async {
    syncCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSalesRepository salesRepo;
  late FakeZohoApiClient zohoApi;
  late FakeSyncWorker syncWorker;
  late FakeHiveDatabaseService fakeDb;
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
    fakeDb = FakeHiveDatabaseService();
    zohoApi = FakeZohoApiClient(dbService: fakeDb);
    syncWorker = FakeSyncWorker(dbService: fakeDb, apiClient: zohoApi);
    bloc = GpsCaptureBloc(
      salesRepository: salesRepo,
      zohoApiClient: zohoApi,
      syncWorker: syncWorker,
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
          final List<dynamic> permissions = methodCall.arguments;
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

    // Verify local cache updated
    expect(salesRepo.lastCustomerId, 'cust_01');
    expect(salesRepo.lastLatitude, 12.3456);

    // Verify Zoho API updated directly
    expect(zohoApi.lastCustomerId, 'cust_01');
    expect(zohoApi.lastLatitude, 12.3456);

    // Verify no sync queued
    expect(salesRepo.queue.isEmpty, true);
    expect(syncWorker.syncCount, 0);
  });

  test('GpsCaptureRequested in persist mode enqueues sync item if Zoho API throws', () async {
    zohoApi.shouldThrow = true;

    final future = bloc.stream.firstWhere((state) => state is GpsCaptureSuccess);
    bloc.add(GpsCaptureRequested(customer: testCustomer, persist: true));
    final state = await future as GpsCaptureSuccess;

    expect(state.latitude, 12.3456);

    // Verify local cache updated
    expect(salesRepo.lastCustomerId, 'cust_01');

    // Verify Zoho API did NOT complete
    expect(zohoApi.lastCustomerId, isNull);

    // Verify sync was queued
    expect(salesRepo.queue.length, 1);
    expect(salesRepo.queue.first.type, 'customer_gps_update');
    expect(salesRepo.queue.first.payload['contact_id'], 'cust_01');
    expect(syncWorker.syncCount, 1);
  });

  test('GpsCaptureRequested in persist mode enqueues sync item for temp_ customer automatically', () async {
    final tempCustomer = testCustomer.copyWith(id: 'temp_cust_123');

    final future = bloc.stream.firstWhere((state) => state is GpsCaptureSuccess);
    bloc.add(GpsCaptureRequested(customer: tempCustomer, persist: true));
    final state = await future as GpsCaptureSuccess;

    expect(state.latitude, 12.3456);

    // Verify local cache updated
    expect(salesRepo.lastCustomerId, 'temp_cust_123');

    // Verify Zoho API was NOT called for temp customer
    expect(zohoApi.lastCustomerId, isNull);

    // Verify sync was queued
    expect(salesRepo.queue.length, 1);
    expect(salesRepo.queue.first.payload['contact_id'], 'temp_cust_123');
    expect(syncWorker.syncCount, 1);
  });
}
