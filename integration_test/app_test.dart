import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:van_sales/app.dart';
import 'package:van_sales/ui/features/auth/views/login_page.dart';
import 'package:van_sales/ui/features/route/views/route_page.dart';
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
  Future<User?> signIn(String email, String password) async {
    _currentUser = User(
      id: 'usr_mock_123',
      name: 'Agent Nellon',
      email: email,
      role: 'agent',
    );
    return _currentUser;
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
  Future<void> triggerSync() async {}

  @override
  Future<void> refreshMasterData() async {}

  @override
  Future<void> syncMaster(MasterType type) async {}

  @override
  bool hasCoreMasters() => true;
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
  List<SalesInvoice> getLocalInvoices() => [];

  @override
  Future<void> saveLocalInvoice(SalesInvoice invoice) async {}

  @override
  List<SalesOrder> getLocalOrders() => [];

  @override
  Future<void> saveLocalOrder(SalesOrder order) async {}

  @override
  Future<List<SalesOrder>> fetchRemoteOrders() async => [];

  @override
  Future<SalesOrder?> fetchRemoteOrder(String zohoOrderId) async => null;

  @override
  List<ReceiptVoucher> getLocalReceipts() => [];

  @override
  Future<void> saveLocalReceipt(ReceiptVoucher voucher) async {}

  @override
  List<SalesReturn> getLocalReturns() => [];

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) async {}

  @override
  List<ExpenseEntry> getLocalExpenses() => [];

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {}

  @override
  CashClosing? getLocalCashClosing() => null;

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {}

  @override
  List<OpenInvoice> getOpenInvoices({String? customerId}) => [];

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {}

  @override
  List<SyncQueueItem> getSyncQueue() => [];
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
      'Verify complete application login sequence and route picker loading',
      (WidgetTester tester) async {
        // 1. Boot the application widget tree
        await tester.pumpWidget(const VanSalesApp());
        await tester.pumpAndSettle();

        // 2. Expect LoginPage to be loaded and visible
        expect(find.byType(LoginPage), findsOneWidget);

        // 3. Target form inputs and Sign In button
        final emailField = find.byType(TextFormField).first;
        final passwordField = find.byType(TextFormField).at(1);
        final signInButton = find.byType(ElevatedButton);

        expect(emailField, findsOneWidget);
        expect(passwordField, findsOneWidget);
        expect(signInButton, findsOneWidget);

        // 4. Enter agent credentials
        await tester.enterText(emailField, 'agent@nellon.com');
        await tester.enterText(passwordField, 'agent_nellon_123');
        await tester.pumpAndSettle();

        // 5. Trigger form submission
        await tester.tap(signInButton);
        // Pump frame updates and allow animations to settle completely
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 6. Verify Auth state transitions and redirects client to RouteSelectionPage
        expect(find.byType(RouteSelectionPage), findsOneWidget);
        expect(find.text('Downtown Route Sequence A'), findsOneWidget);
      },
    );
  });
}
