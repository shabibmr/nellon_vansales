import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sales_order_model.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/document_number_service.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/repositories/sales_order_repository.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/ui/features/sales_order/bloc/sales_order_editor_bloc.dart';
import 'package:van_sales/ui/features/sales_order/bloc/sales_order_editor_event.dart';

/// Records what the bloc asked for, so the tests can assert that opening a
/// saved order reads Zoho and never the local cache.
class FakeSalesRepository
    with CustomerRepositorySubmitStubs, SalesOrderRepositorySubmitStubs
    implements CustomerRepository, SalesOrderRepository {
  final List<String> fetchedOrderIds = [];
  final List<SyncQueueItem> queue = [];
  final List<SalesOrder> savedOrders = [];

  /// Returned by [fetchRemoteOrder] unless [fetchFailure] is set.
  SalesOrder? remoteOrder;
  Object? fetchFailure;

  @override
  Future<SalesOrder?> fetchRemoteOrder(
    String zohoOrderId, {
    bool allowOfflineFallback = false,
  }) async {
    fetchedOrderIds.add(zohoOrderId);
    if (fetchFailure != null) throw fetchFailure!;
    return remoteOrder;
  }

  @override
  List<SalesOrder> getLocalOrders() => List.of(savedOrders);

  @override
  Future<void> saveLocalOrder(SalesOrder order) async {
    savedOrders.add(order);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<void> enqueueSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  }) async {
    final payload = SalesOrderModel.fromDomain(order).toJson();
    if (isUpdate) {
      final zohoId = order.zohoOrderId;
      if (zohoId != null && zohoId.isNotEmpty) {
        payload['salesorder_id'] = zohoId;
      }
    }
    queue.add(
      SyncQueueItem(
        id: order.id,
        type: isUpdate ? 'update_sales_order' : 'sales_order',
        payload: payload,
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];

  // --- Unused by these tests -------------------------------------------------
  List<Customer> customers = [];

  @override
  List<Customer> getCustomers() => List.of(customers);
  @override
  Future<void> saveCustomers(List<Customer> customers) async {
    this.customers = List.of(customers);
  }
  @override
  Future<void> updateCustomerGps(
    String customerId,
    double latitude,
    double longitude,
  ) async {}
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

class FakeSyncRepository implements SyncRepository {
  int triggerCount = 0;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    triggerCount++;
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
  Future<void> refreshMasterData() async {}
  @override
  Future<void> syncMaster(MasterType type) async {}
  @override
  bool hasCoreMasters() => true;

  @override
  int getMasterRecordCount(MasterType type) => 0;
}

/// Stub for paths that never allocate a new document number.
class FakeDocumentNumberService extends Fake implements DocumentNumberService {
  @override
  Future<String> nextNumber(DocType type) async => 'SO-FAKE-00001';
}

Item _item(String id) => Item(
  id: id,
  name: 'Item $id',
  sku: 'SKU-$id',
  rate: 10,
  stock: 0,
  description: '',
  taxName: 'VAT',
  taxPercentage: 5,
  uom: 'pcs',
);

OrderLineItem _line(String itemId, double qty) => OrderLineItem(
  item: _item(itemId),
  quantity: qty,
  rate: 10,
  taxPercentage: 5,
);

SalesOrder _order({
  required String id,
  String orderNumber = 'SO-00001',
  List<OrderLineItem> items = const [],
  bool isPendingSync = false,
  String? zohoOrderId,
  String? locationId,
}) => SalesOrder(
  id: id,
  orderNumber: orderNumber,
  customerId: 'cust_1',
  customerName: 'Acme',
  date: DateTime(2026, 7, 1),
  shipmentDate: DateTime(2026, 7, 5),
  items: items,
  notes: 'note',
  isPendingSync: isPendingSync,
  zohoOrderId: zohoOrderId,
  locationId: locationId,
);

void main() {
  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late FakeDocumentNumberService docNumbers;
  late SalesOrderEditorBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    docNumbers = FakeDocumentNumberService();
    bloc = SalesOrderEditorBloc(
      salesOrderRepository: salesRepo,
      customerRepository: salesRepo,
      documentNumberService: docNumbers,
    );
  });

  tearDown(() async => bloc.close());

  group('opening an order', () {
    test('a saved order is read from Zoho, not from the list copy', () async {
      // The list endpoint carries no line_items — the cached object is stale on
      // purpose, so any fallback to it would show one line instead of two.
      final fromList = _order(id: 'so_9001', items: [_line('item_1', 1)]);
      salesRepo.remoteOrder = _order(
        id: 'so_9001',
        items: [_line('item_1', 4), _line('item_2', 7)],
        zohoOrderId: 'so_9001',
      );

      bloc.add(OpenSalesOrder(fromList));
      await bloc.stream.firstWhere((s) => !s.isEditorLoading);

      expect(salesRepo.fetchedOrderIds, ['so_9001']);
      expect(bloc.state.editingItems.length, 2);
      expect(bloc.state.editingItems.first.quantity, 4);
      expect(bloc.state.editingOrder?.zohoOrderId, 'so_9001');
      expect(bloc.state.editorError, isNull);
    });

    test('an order still pending sync opens locally without a fetch', () async {
      final local = _order(
        id: 'temp_so_123',
        items: [_line('item_1', 3)],
        isPendingSync: true,
      );

      bloc.add(OpenSalesOrder(local));
      await bloc.stream.first;

      expect(salesRepo.fetchedOrderIds, isEmpty);
      expect(bloc.state.isEditorLoading, isFalse);
      expect(bloc.state.editingItems.single.quantity, 3);
    });

    test('open hydrates customer from masters when available', () async {
      salesRepo.customers = [
        Customer(
          id: 'cust_1',
          name: 'Acme Trading',
          companyName: 'Acme LLC',
          email: 'a@acme.test',
          phone: '555',
          address: '1 Main',
          outstandingBalance: 12,
          creditLimit: 5000,
          routeId: 'r1',
          sequence: 3,
        ),
      ];
      final local = _order(
        id: 'temp_so_9',
        items: [_line('item_1', 1)],
        isPendingSync: true,
      );

      bloc.add(OpenSalesOrder(local));
      await bloc.stream.first;

      expect(bloc.state.editingCustomer?.companyName, 'Acme LLC');
      expect(bloc.state.editingCustomer?.creditLimit, 5000);
      expect(bloc.state.editingCustomer?.email, 'a@acme.test');
    });

    test('a failed fetch surfaces an error and Retry re-issues it', () async {
      salesRepo.fetchFailure = Exception('Network unreachable');

      bloc.add(OpenSalesOrder(_order(id: 'so_9001')));
      await bloc.stream.firstWhere((s) => !s.isEditorLoading);

      expect(bloc.state.editorError, isNotNull);
      expect(bloc.state.editingItems, isEmpty);
      // No stale copy leaked in from the list object.
      expect(bloc.state.editingOrder, isNull);

      salesRepo.fetchFailure = null;
      salesRepo.remoteOrder = _order(
        id: 'so_9001',
        items: [_line('item_1', 2)],
        zohoOrderId: 'so_9001',
      );

      bloc.add(const RetryLoadSalesOrder());
      await bloc.stream.firstWhere(
        (s) => !s.isEditorLoading && s.editorError == null,
      );

      expect(salesRepo.fetchedOrderIds, ['so_9001', 'so_9001']);
      expect(bloc.state.editingItems.single.quantity, 2);
    });
  });

  test('saving a fetched order queues an update, not a create', () async {
    salesRepo.remoteOrder = _order(
      id: 'so_9001',
      orderNumber: 'SO-00042',
      items: [_line('item_1', 4)],
      zohoOrderId: 'so_9001',
    );

    bloc.add(OpenSalesOrder(_order(id: 'so_9001')));
    await bloc.stream.firstWhere((s) => !s.isEditorLoading);

    bloc.add(const SaveSalesOrder(notes: 'updated'));
    await bloc.stream.firstWhere((s) => s.successMessage != null);

    expect(salesRepo.queue.length, 1);
    final queued = salesRepo.queue.single;
    expect(queued.type, 'update_sales_order');
    expect(queued.payload['salesorder_id'], 'so_9001');
    // The original number is kept — an update must not renumber the order.
    expect(queued.payload['salesorder_number'], 'SO-00042');
  });

  test('saving a fetched order keeps its locationId', () async {
    // Regression: _onSaveOrder used to rebuild the SalesOrder without
    // carrying forward locationId, silently dropping it on every edit.
    salesRepo.remoteOrder = _order(
      id: 'so_9001',
      items: [_line('item_1', 4)],
      zohoOrderId: 'so_9001',
      locationId: 'warehouse_van_7',
    );

    bloc.add(OpenSalesOrder(_order(id: 'so_9001')));
    await bloc.stream.firstWhere((s) => !s.isEditorLoading);
    expect(bloc.state.editingOrder?.locationId, 'warehouse_van_7');

    bloc.add(const SaveSalesOrder(notes: 'updated'));
    await bloc.stream.firstWhere((s) => s.successMessage != null);

    expect(salesRepo.savedOrders, isEmpty);
    expect(salesRepo.queue.single.payload['location_id'], 'warehouse_van_7');
  });

  test('saving a new order queues a create with a document number', () async {
    const customer = Customer(
      id: 'cust_1',
      name: 'Acme',
      companyName: 'Acme LLC',
      email: '',
      phone: '',
      address: '',
      outstandingBalance: 0,
      creditLimit: 1000,
      routeId: 'r1',
      sequence: 1,
    );

    bloc.add(const StartNewSalesOrder(customer: customer));
    await bloc.stream.first;
    bloc.add(
      AddOrUpdateOrderLine(
        item: _item('item_1'),
        quantity: 2,
      ),
    );
    await bloc.stream.first;

    bloc.add(const SaveSalesOrder(notes: 'new order'));
    await bloc.stream.firstWhere((s) => s.successMessage != null);

    expect(salesRepo.queue, hasLength(1));
    final queued = salesRepo.queue.single;
    expect(queued.type, 'sales_order');
    expect(queued.payload['salesorder_number'], 'SO-FAKE-00001');
    // Create path must not stamp a permanent Zoho id onto the payload.
    expect(queued.payload['salesorder_id'], isNot(equals('so_9001')));
    expect(salesRepo.savedOrders, isEmpty);
  });

  test('saving a converted order is rejected without enqueue', () async {
    salesRepo.remoteOrder = SalesOrder(
      id: 'so_9001',
      orderNumber: 'SO-00099',
      customerId: 'cust_1',
      customerName: 'Acme',
      date: DateTime(2026, 7, 1),
      shipmentDate: DateTime(2026, 7, 5),
      items: [_line('item_1', 1)],
      notes: '',
      zohoOrderId: 'so_9001',
      status: SalesOrderStatus.invoiced,
      convertedInvoiceNumber: 'INV-1',
    );

    bloc.add(OpenSalesOrder(_order(id: 'so_9001')));
    await bloc.stream.firstWhere((s) => !s.isEditorLoading);
    expect(bloc.state.isConverted, isTrue);

    bloc.add(const SaveSalesOrder(notes: 'should fail'));
    await bloc.stream.firstWhere((s) => s.errorMessage != null);

    expect(bloc.state.errorMessage, contains('converted'));
    expect(salesRepo.queue, isEmpty);
    expect(syncRepo.triggerCount, 0);
  });
}
