import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/document_number_service.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/customer_ledger.dart';
import 'package:van_sales/domain/repositories/receipt_repository.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/ui/features/receipts/bloc/receipt_editor_bloc.dart';
import 'package:van_sales/ui/features/receipts/bloc/receipt_editor_event.dart';
import 'package:van_sales/ui/features/receipts/bloc/receipt_list_bloc.dart';
import 'package:van_sales/ui/features/receipts/bloc/receipt_list_event.dart';

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
    with CustomerRepositorySubmitStubs, ReceiptRepositorySubmitStubs
    implements CustomerRepository, ReceiptRepository {
  List<OpenInvoice> openInvoices = [];
  List<Customer> customers = [];
  List<ReceiptVoucher> receipts = [];
  List<SyncQueueItem> syncQueue = [];

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) {
    if (customerId != null) {
      return openInvoices.where((i) => i.customerId == customerId).toList();
    }
    return openInvoices;
  }

  int fetchRemoteOpenInvoicesCount = 0;
  bool throwOnFetchRemoteOpenInvoices = false;

  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async {
    fetchRemoteOpenInvoicesCount++;
    if (throwOnFetchRemoteOpenInvoices) throw Exception('offline');
    return getOpenInvoices(customerId: customerId);
  }

  @override
  List<Customer> getCustomers() => customers;

  @override
  List<ReceiptVoucher> getLocalReceipts() => receipts;

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {
    receipts.add(voucher);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    syncQueue.add(item);
  }

  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      receipts;

  @override
  Future<ReceiptVoucher?> fetchReceiptById(
    String paymentId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    try {
      return receipts.firstWhere((r) => r.id == paymentId);
    } catch (_) {
      return null;
    }
  }

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

Customer _cust(String id, String name) => Customer(
      id: id,
      name: name,
      companyName: '',
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
  late DocumentNumberService docNumbers;

  setUp(() {
    final sl = GetIt.instance;
    if (sl.isRegistered<DocumentNumberService>()) {
      sl.unregister<DocumentNumberService>();
    }
    docNumbers = DocumentNumberService(
      dbService: _FakeDocDb(),
      apiClient: _FakeZohoApi(),
    );
    sl.registerSingleton<DocumentNumberService>(docNumbers);

    salesRepo = FakeSalesRepository();
  });

  tearDown(() {
    final sl = GetIt.instance;
    if (sl.isRegistered<DocumentNumberService>()) {
      sl.unregister<DocumentNumberService>();
    }
  });

  group('ReceiptListBloc', () {
    test('LoadReceipts fetches remote receipts for current date range', () async {
      salesRepo.receipts = [
        ReceiptVoucher(
          id: 'pay_1',
          paymentNumber: 'PAY-001',
          customerId: 'c1',
          customerName: 'Cust 1',
          date: DateTime.now(),
          amount: 100,
          paymentMode: 'Cash',
          referenceNumber: '',
          allocations: const [],
        ),
      ];

      final bloc = ReceiptListBloc(receiptRepository: salesRepo);
      bloc.add(const LoadReceipts());

      await bloc.stream.firstWhere((s) => !s.isLoading);
      expect(bloc.state.receipts, hasLength(1));
      bloc.close();
    });
  });

  group('ReceiptEditorBloc', () {
    test('StartNewReceipt initializes blank form state', () async {
      final bloc = ReceiptEditorBloc(
        receiptRepository: salesRepo,
        customerRepository: salesRepo,
        documentNumberService: docNumbers,
      );
      bloc.add(const StartNewReceipt());
      final state = await bloc.stream.firstWhere((s) => s.isEditingNew);

      expect(state.isEditingNew, isTrue);
      expect(state.editingCustomer, isNull);
      expect(state.editingAmount, 0.0);
      bloc.close();
    });

    test('SaveReceipt saves local receipt and enqueues sync queue item', () async {
      final bloc = ReceiptEditorBloc(
        receiptRepository: salesRepo,
        customerRepository: salesRepo,
        documentNumberService: docNumbers,
      );

      final customer = _cust('c1', 'Acme');
      bloc.add(StartNewReceipt(customer: customer));
      bloc.add(const SetEditingAmount(150.0));
      bloc.add(const SaveReceipt());

      await bloc.stream.firstWhere((s) => s.successMessage != null);

      expect(salesRepo.receipts, isEmpty);
      expect(salesRepo.syncQueue, hasLength(1));
      expect(salesRepo.syncQueue.single.type, 'receipt');
      bloc.close();
    });
  });
}
