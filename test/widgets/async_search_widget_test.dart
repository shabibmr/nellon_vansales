import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/repositories/item_repository.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/core/cubit/organization_cubit.dart';
import 'package:van_sales/ui/core/widgets/async_search_widget.dart';
import 'package:van_sales/ui/core/widgets/customer_missing_fields_dialog.dart';

class _FakeOrgCubit extends Cubit<Organization?> implements OrganizationCubit {
  _FakeOrgCubit() : super(null);

  @override
  String get currencySymbol => 'AED';

  @override
  String get companyName => 'Test Co';

  @override
  String get currencyCode => 'AED';

  @override
  void refresh() {}
}

class _FakeSalesRepository implements CustomerRepository, ItemRepository {
  List<Customer> customers = [];
  String? savedPhone;
  String? savedTrn;
  bool remotePushed = false;

  @override
  List<Customer> getCustomers() => customers;

  @override
  Future<({Customer customer, bool offlineFallback})> resolveCustomerDetails(
    Customer customer,
  ) async =>
      (customer: customer, offlineFallback: false);

  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    savedPhone = phone;
    savedTrn = trn;
  }

  @override
  Future<void> pushCustomerContactFieldsRemote(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    remotePushed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (invocation.isGetter) {
      if (name.contains('Stream')) return const Stream.empty();
      if (name.contains('isSyncing') || name.contains('hasPending')) {
        return false;
      }
      if (name.contains('hasCore')) return true;
      return null;
    }
    if (name.contains('List') ||
        name.contains('getLocal') ||
        name.contains('getItems') ||
        name.contains('getRoutes') ||
        name.contains('getSync') ||
        name.contains('getOpen') ||
        name.contains('getWarehouses')) {
      return [];
    }
    return null;
  }
}

class _FakeSyncRepository implements SyncRepository {
  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {}

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

Customer _customer({
  String name = 'Shop A',
  String phone = '',
  String trn = '',
  double? latitude,
  double? longitude,
}) {
  return Customer(
    id: 'c1',
    name: name,
    companyName: 'Co A',
    email: '',
    phone: phone,
    address: '',
    trn: trn,
    outstandingBalance: 0,
    creditLimit: 0,
    routeId: 'r1',
    sequence: 1,
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  late _FakeSalesRepository sales;
  late _FakeSyncRepository sync;

  setUp(() {
    sales = _FakeSalesRepository();
    sync = _FakeSyncRepository();
  });

  Future<void> pumpSearch(
    WidgetTester tester, {
    required List<Customer> customers,
    required ValueChanged<Customer> onSelected,
  }) async {
    sales.customers = customers;
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CustomerRepository>.value(value: sales),
          RepositoryProvider<ItemRepository>.value(value: sales),
          RepositoryProvider<SyncRepository>.value(value: sync),
        ],
        child: MaterialApp(
          home: BlocProvider<OrganizationCubit>.value(
            value: _FakeOrgCubit(),
            child: Scaffold(
              body: AsyncSearchWidget(onCustomerSelected: onSelected),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Shop');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('complete customer is selected without a prompt', (tester) async {
    Customer? selected;
    await pumpSearch(
      tester,
      customers: [
        _customer(
          phone: '0501234567',
          trn: '100533986400003',
          latitude: 25.1,
          longitude: 55.2,
        ),
      ],
      onSelected: (c) => selected = c,
    );

    await tester.tap(find.text('Shop A'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected?.id, 'c1');
  });

  testWidgets(
    'missing location, TRN or phone opens a dialog with skip, save and cancel',
    (tester) async {
      await pumpSearch(
        tester,
        customers: [_customer()],
        onSelected: (_) {},
      );

      await tester.tap(find.text('Shop A'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerMissingFieldsDialog), findsOneWidget);
      expect(find.text('Complete Customer Details'), findsOneWidget);
      expect(find.text('SKIP'), findsOneWidget);
      expect(find.text('SAVE'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
    },
  );

  testWidgets('skip selects the customer without sending to Zoho',
      (tester) async {
    Customer? selected;
    await pumpSearch(
      tester,
      customers: [_customer()],
      onSelected: (c) => selected = c,
    );

    await tester.tap(find.text('Shop A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected?.id, 'c1');
    expect(sales.savedPhone, isNull);
    expect(sales.remotePushed, isFalse);
  });

  testWidgets('cancel leaves the customer unselected', (tester) async {
    Customer? selected;
    await pumpSearch(
      tester,
      customers: [_customer()],
      onSelected: (c) => selected = c,
    );

    await tester.tap(find.text('Shop A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected, isNull);
    expect(sales.remotePushed, isFalse);
  });

  testWidgets('save persists missing phone to Zoho and selects the customer',
      (tester) async {
    Customer? selected;
    await pumpSearch(
      tester,
      customers: [
        _customer(
          trn: '100533986400003',
          latitude: 25.1,
          longitude: 55.2,
        ),
      ],
      onSelected: (c) => selected = c,
    );

    await tester.tap(find.text('Shop A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '0501234567');
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected?.phone, '0501234567');
    expect(sales.savedPhone, '0501234567');
    expect(sales.remotePushed, isTrue);
  });
}
