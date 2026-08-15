import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:van_sales/app.dart';
import 'package:van_sales/ui/features/auth/views/login_page.dart';
import 'package:van_sales/domain/models/phone_auth_event.dart';
import 'package:van_sales/domain/repositories/auth_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/domain/repositories/sales_repository.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/domain/models/user.dart';
import 'package:van_sales/domain/models/route.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:get_it/get_it.dart';

// Fake implementations to isolate E2E UI rendering from disk/network IO
class FakeAuthRepository implements AuthRepository {
  User? _currentUser;

  @override
  Stream<User?> get onAuthStateChanged => Stream.value(_currentUser);

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<PhoneAuthEvent> startPhoneVerification(
    String e164Phone, {
    int? forceResendingToken,
  }) {
    final controller = StreamController<PhoneAuthEvent>();
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          const PhoneCodeSent(verificationId: 'vid_mock', resendToken: 1),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<User?> signInWithSmsCode(String verificationId, String smsCode) async {
    _currentUser = const User(
      id: 'usr_mock_123',
      name: 'Agent Nellon',
      email: '',
      phone: '+971542891246',
      role: 'agent',
    );
    return _currentUser;
  }

  @override
  Future<User?> signInWithPhoneCredential(
    fb.PhoneAuthCredential credential,
  ) async {
    return signInWithSmsCode('auto', '000000');
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class FakeSyncRepository implements SyncRepository {
  @override
  Stream<String> get syncStatusStream => const Stream.empty();

  @override
  Stream<int> get syncCountStream => const Stream.empty();

  @override
  bool get isSyncing => false;

  @override
  List<SyncQueueItem> getSyncQueue() => [];

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {}

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

class FakeSalesRepository implements SalesRepository {
  @override
  List<RouteModel> getRoutes() => [
    const RouteModel(
      id: 'rt_01',
      name: 'Downtown Route Sequence A',
      description: 'Downtown route sequence',
    ),
  ];

  @override
  String? get activeRouteId => 'rt_01';

  @override
  Future<void> setActiveRouteId(String? routeId) async {}

  @override
  List<Customer> getCustomers() => [];

  @override
  Future<void> saveCustomers(List<Customer> customers) async {}

  @override
  List<Item> getItems() => [];

  @override
  Future<void> saveItems(List<Item> items) async {}

  @override
  Future<({Item item, bool offlineFallback})> resolveItemUnitConversions(
    Item item,
  ) async =>
      (item: item, offlineFallback: false);

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  ) async =>
      (customer: customer, offlineFallback: false);

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
  List<ReceiptVoucher> getLocalReceipts() => [];

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}

  @override
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];

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
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];
  @override
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId}) async =>
      [];

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}

  @override
  Future<void> enqueueSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  }) async {}

  @override
  List<SyncQueueItem> getSyncQueue() => [];

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
  List<StockTransfer> getLocalStockTransfers() => [];

  @override
  Future<void> saveLocalStockTransfer(StockTransfer transfer) async {}

  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Van Sales End-to-End UI Integration Test', () {
    setUpAll(() {
      final sl = GetIt.instance;
      // Register Fakes inside Service Locator container prior to application loading
      sl.registerLazySingleton<AuthRepository>(() => FakeAuthRepository());
      sl.registerLazySingleton<SyncRepository>(() => FakeSyncRepository());
      sl.registerLazySingleton<SalesRepository>(() => FakeSalesRepository());
    });

    testWidgets(
      'Verify phone OTP login surface loads (phone step)',
      (WidgetTester tester) async {
        // 1. Boot the application widget tree
        await tester.pumpWidget(const VanSalesApp());
        await tester.pumpAndSettle();

        // 2. Expect LoginPage with phone OTP entry (not email/password)
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text('SEND CODE'), findsOneWidget);
        expect(find.byType(TextFormField), findsOneWidget);
        expect(find.textContaining('Mobile Number'), findsOneWidget);
      },
    );
  });
}
