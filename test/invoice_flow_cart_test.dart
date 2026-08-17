import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/document_number_service.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/repositories/invoice_repository.dart';
import 'package:van_sales/domain/repositories/sales_order_repository.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_editor_bloc.dart';
import 'package:van_sales/ui/features/sales_invoice/bloc/sales_invoice_editor_event.dart';

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

  int getNextSequence(String key) {
    final next = (_counters[key] ?? 0) + 1;
    _counters[key] = next;
    return next;
  }
}

class _FakeZohoApi extends ZohoApiClient {
  _FakeZohoApi() : super(dbService: _FakeDocDb());
}

class FakeSalesRepository
    with
        CustomerRepositorySubmitStubs,
        InvoiceRepositorySubmitStubs,
        SalesOrderRepositorySubmitStubs
    implements CustomerRepository, InvoiceRepository, SalesOrderRepository {
  final List<SalesInvoice> invoices = [];
  final List<SyncQueueItem> queue = [];
  bool throwOnSave = false;

  @override
  List<SalesInvoice> getLocalInvoices() => List.from(invoices);

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {
    if (throwOnSave) throw Exception('save failed');
    invoices.add(invoice);
  }

  @override
  Future<SalesInvoice?> fetchInvoiceById(
    String invoiceId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    try {
      return invoices.firstWhere((i) => i.id == invoiceId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      [];

  @override
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate}) async {}
  @override
  List<SalesOrder> getLocalOrders() => [];
  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}
  @override
  Future<List<SalesOrder>> fetchRemoteOrders({DateTime? startDate, DateTime? endDate}) async => [];
  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId, {bool allowOfflineFallback = false}) async => null;
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

Item _item({
  required String id,
  required String name,
  double rate = 10.0,
  double stock = 10.0,
  double tax = 5.0,
}) =>
    Item(
      id: id,
      name: name,
      sku: 'SKU-$id',
      rate: rate,
      stock: stock,
      description: '',
      taxName: 'VAT',
      taxPercentage: tax,
      uom: 'pcs',
    );

Customer _customer() => const Customer(
      id: 'c1',
      name: 'Acme Trader',
      companyName: 'Acme',
      email: '',
      phone: '',
      address: 'x',
      outstandingBalance: 0,
      creditLimit: 1000,
      routeId: 'r1',
      sequence: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSalesRepository salesRepo;
  late SalesInvoiceEditorBloc bloc;

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
    bloc = SalesInvoiceEditorBloc(
      invoiceRepository: salesRepo,
      salesOrderRepository: salesRepo,
      customerRepository: salesRepo,
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

  test('StartNewInvoice clears form so sheet opens clean', () async {
    final item = _item(id: 'i1', name: 'Widget');
    bloc.add(AddOrUpdateLineItem(item: item, quantity: 2));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    bloc.add(const StartNewInvoice());
    final cleared = await bloc.stream.firstWhere((s) => s.editingItems.isEmpty);
    expect(cleared.editingItems, isEmpty);
  });

  test('AddOrUpdateLineItem over stock emits error and leaves items unchanged', () async {
    final item = _item(id: 'i1', name: 'Widget', stock: 1);
    bloc.add(AddOrUpdateLineItem(item: item, quantity: 1));
    await bloc.stream.firstWhere((s) => s.editingItems.length == 1);

    bloc.add(AddOrUpdateLineItem(item: item, quantity: 2));
    final rejected = await bloc.stream.firstWhere((s) => s.errorMessage != null);

    expect(rejected.errorMessage, contains('only 1 available'));
    expect(rejected.editingItems.single.quantity, 1);
  });

  test('SaveInvoice generates document number and enqueues sync item', () async {
    final cust = _customer();
    final item = _item(id: 'i1', name: 'Widget', rate: 10, tax: 5);

    bloc.add(StartNewInvoice(customer: cust));
    await bloc.stream.firstWhere((s) => s.editingCustomer?.id == 'c1');

    bloc.add(AddOrUpdateLineItem(item: item, quantity: 3));
    await bloc.stream.firstWhere((s) => s.editingItems.isNotEmpty);

    bloc.add(const SaveInvoice(notes: 'Van Sales Checkout'));
    final savedState = await bloc.stream.firstWhere(
      (s) => s.successMessage != null,
    );

    expect(savedState.successMessage, 'Saved to upload queue');
    expect(salesRepo.invoices, isEmpty);
    expect(salesRepo.queue, hasLength(1));
    expect(salesRepo.queue.single.type, 'invoice');
  });
}
