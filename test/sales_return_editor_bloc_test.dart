import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/document_number_service.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/sales_return_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/features/sales_return/bloc/sales_return_editor_bloc.dart';
import 'package:van_sales/ui/features/sales_return/bloc/sales_return_editor_event.dart';

class _FakeDocDb extends HiveDatabaseService {
  final Map<String, int> _counters = {};

  @override
  String? get voucherPrefix => 'SHB-';

  @override
  int? getDocCounter(String tag) => _counters[tag];

  @override
  Future<void> setDocCounter(String tag, int value) async {
    _counters[tag] = value;
  }

  @override
  int getNextSequence(String key) {
    final next = (_counters[key] ?? 0) + 1;
    _counters[key] = next;
    return next;
  }
}

class _FakeZohoApi extends ZohoApiClient {
  _FakeZohoApi() : super(dbService: _FakeDocDb());
}

class FakeSalesRepository implements CustomerRepository, SalesReturnRepository {
  List<SalesReturn> returns = [];
  List<SyncQueueItem> queue = [];

  @override
  List<SalesReturn> getLocalReturns() => List.of(returns);

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {
    returns.add(salesReturn);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<SalesReturn?> fetchSalesReturnById(
    String creditNoteId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    try {
      return returns.firstWhere((r) => r.id == creditNoteId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      returns;

  @override
  List<Customer> getCustomers() => [];
  @override
  Future<void> saveCustomers(List<Customer> customers) async {}
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
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  ) async =>
      (customer: customer, offlineFallback: false);
  @override
  Future<CustomerLedger> fetchCustomerLedger(String customerId, {DateTime? startDate, DateTime? endDate}) => throw UnimplementedError();
  @override
  Customer? getCustomerById(String id) => null;
  @override
  Future<void> pushCustomerGpsRemote(String customerId, double latitude, double longitude) => throw UnimplementedError();
}

class FakeSyncRepository implements SyncRepository {
  int triggerCount = 0;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
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

Item _item(String id) => Item(
      id: id,
      name: 'Item $id',
      sku: 'SKU-$id',
      rate: 20,
      stock: 100,
      description: '',
      taxName: 'VAT',
      taxPercentage: 5,
      uom: 'pcs',
    );

Customer _customer() => const Customer(
      id: 'c1',
      name: 'Acme Trader',
      companyName: 'Acme',
      email: '',
      phone: '',
      address: '',
      outstandingBalance: 0,
      creditLimit: 1000,
      routeId: '',
      sequence: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late SalesReturnEditorBloc bloc;

  setUp(() {
    final sl = GetIt.instance;
    if (sl.isRegistered<DocumentNumberService>()) {
      sl.unregister<DocumentNumberService>();
    }
    sl.registerSingleton<DocumentNumberService>(
      DocumentNumberService(
        dbService: _FakeDocDb(),
        apiClient: _FakeZohoApi(),
      ),
    );

    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    bloc = SalesReturnEditorBloc(
      salesReturnRepository: salesRepo,
      customerRepository: salesRepo,
      syncRepository: syncRepo,
      documentNumberService: sl<DocumentNumberService>(),
    );
  });

  tearDown(() async {
    await bloc.close();
    final sl = GetIt.instance;
    if (sl.isRegistered<DocumentNumberService>()) {
      sl.unregister<DocumentNumberService>();
    }
  });

  test('StartNewReturn initializes form defaults', () async {
    final cust = _customer();
    bloc.add(StartNewReturn(customer: cust));
    final state = await bloc.stream.firstWhere((s) => s.isEditingNew);

    expect(state.isEditingNew, isTrue);
    expect(state.editingCustomer?.id, 'c1');
    expect(state.editingItems, isEmpty);
  });

  test('SaveReturn saves local return and enqueues sync queue item', () async {
    final cust = _customer();
    final item = _item('i1');

    bloc.add(StartNewReturn(customer: cust));
    bloc.add(AddOrUpdateReturnLineItem(item: item, quantity: 2));
    bloc.add(const SaveReturn(reason: 'Expired stock'));

    await bloc.stream.firstWhere((s) => s.successMessage != null);

    expect(salesRepo.returns, hasLength(1));
    final saved = salesRepo.returns.single;
    expect(saved.creditNoteNumber, startsWith('SHB-CN-'));
    expect(saved.customerId, 'c1');
    expect(saved.reason, 'Expired stock');

    expect(salesRepo.queue, hasLength(1));
    expect(syncRepo.triggerCount, 1);
  });
}
