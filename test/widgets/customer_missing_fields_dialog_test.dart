import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/submit_result.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/core/bloc/gps_capture_bloc.dart';
import 'package:van_sales/ui/core/widgets/customer_missing_fields_dialog.dart';
import '../helpers/sales_repository_enqueue_stubs.dart';

class _FakeSalesRepository
    with CustomerRepositorySubmitStubs
    implements CustomerRepository {
  String? savedPhone;
  String? savedTrn;
  String? savedId;
  bool remotePushed = false;
  String? remotePhone;
  String? remoteTrn;
  final List<SyncQueueItem> queue = [];

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<SubmitResult> submitOrEnqueue(SyncQueueItem item) async {
    savedId = item.payload['contact_id']?.toString();
    if (item.type == 'customer_contact_update') {
      savedPhone = item.payload['phone']?.toString();
      savedTrn = item.payload['tax_reg_no']?.toString();
    }
    await enqueueSyncItem(item);
    return SubmitResult.queued;
  }

  @override
  Future<void> updateCustomerContactFields(
    String customerId, {
    String? phone,
    String? trn,
  }) async {
    savedId = customerId;
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
    remotePhone = phone;
    remoteTrn = trn;
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
        name.contains('getCustomers') ||
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
  String phone = '',
  String trn = '',
  double? latitude,
  double? longitude,
}) {
  return Customer(
    id: 'c1',
    name: 'Shop A',
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

  /// Opens the dialog and returns the (still-pending) [Future] that will
  /// resolve once the dialog is closed, so callers can interact with the
  /// dialog further before awaiting the result.
  Future<Future<Customer?>> pumpDialog(
    WidgetTester tester,
    Customer customer,
  ) async {
    late Future<Customer?> resultFuture;
    final missing = CustomerMissingFields.of(customer);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CustomerRepository>.value(value: sales),
          RepositoryProvider<SyncRepository>.value(value: sync),
        ],
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => GpsCaptureBloc(
              customerRepository: sales,
              syncRepository: sync,
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    resultFuture = showDialog<Customer>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => BlocProvider.value(
                        value: context.read<GpsCaptureBloc>(),
                        child: CustomerMissingFieldsDialog(
                          customer: customer,
                          missing: missing,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return resultFuture;
  }

  testWidgets('GPS-only customer shows capture, not phone or TRN',
      (tester) async {
    await pumpDialog(
      tester,
      _customer(phone: '0501234567', trn: '100533986400003'),
    );

    expect(find.text('Add GPS Location'), findsOneWidget);
    expect(find.text('CAPTURE GPS'), findsOneWidget);
    expect(find.text('Phone Number'), findsNothing);
    expect(find.text('TRN Number'), findsNothing);
    expect(find.text('SAVE'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'SAVE')).onPressed,
      isNull,
    );
  });

  testWidgets('phone-only customer shows phone field, not GPS or TRN',
      (tester) async {
    await pumpDialog(
      tester,
      _customer(
        trn: '100533986400003',
        latitude: 25.1,
        longitude: 55.2,
      ),
    );

    expect(find.text('Add Phone Number'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('CAPTURE GPS'), findsNothing);
    expect(find.text('TRN Number'), findsNothing);
    expect(find.text('SAVE'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'SAVE')).onPressed,
      isNull,
    );
  });

  testWidgets('TRN-only customer shows TRN field, not GPS or phone',
      (tester) async {
    await pumpDialog(
      tester,
      _customer(
        phone: '0501234567',
        latitude: 25.1,
        longitude: 55.2,
      ),
    );

    expect(find.text('Add TRN Number'), findsOneWidget);
    expect(find.text('TRN Number'), findsOneWidget);
    expect(find.text('Phone Number'), findsNothing);
    expect(find.text('CAPTURE GPS'), findsNothing);
  });

  testWidgets('all missing shows GPS, phone and TRN together', (tester) async {
    await pumpDialog(tester, _customer());

    expect(find.text('Complete Customer Details'), findsOneWidget);
    expect(find.text('CAPTURE GPS'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('TRN Number'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
  });

  testWidgets('skip closes GPS-only prompt without capturing location',
      (tester) async {
    final resultFuture = await pumpDialog(
      tester,
      _customer(phone: '0501234567', trn: '100533986400003'),
    );

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    final selected = await resultFuture;

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected?.latitude, isNull);
    expect(selected?.longitude, isNull);
  });

  testWidgets('skip closes prompt with all fields missing, discarding unsaved text',
      (tester) async {
    final resultFuture = await pumpDialog(tester, _customer());

    await tester.enterText(find.byType(TextFormField).first, '0501234567');
    await tester.pump();

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    final selected = await resultFuture;

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected?.phone, '');
    expect(selected?.trn, '');
    expect(selected?.latitude, isNull);
    expect(sales.savedPhone, isNull);
  });

  testWidgets('cancel closes without saving or selecting', (tester) async {
    final resultFuture = await pumpDialog(
      tester,
      _customer(
        trn: '100533986400003',
        latitude: 25.1,
        longitude: 55.2,
      ),
    );

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    final selected = await resultFuture;

    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
    expect(selected, isNull);
    expect(sales.savedPhone, isNull);
    expect(sales.remotePushed, isFalse);
  });

  testWidgets('saving a missing phone persists and pops the dialog',
      (tester) async {
    Customer? selected;
    final customer = _customer(
      trn: '100533986400003',
      latitude: 25.1,
      longitude: 55.2,
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CustomerRepository>.value(value: sales),
          RepositoryProvider<SyncRepository>.value(value: sync),
        ],
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => GpsCaptureBloc(
              customerRepository: sales,
              syncRepository: sync,
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await showDialog<Customer>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => BlocProvider.value(
                        value: context.read<GpsCaptureBloc>(),
                        child: CustomerMissingFieldsDialog(
                          customer: customer,
                          missing: CustomerMissingFields.of(customer),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '0501234567');
    await tester.pump();

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(sales.savedId, 'c1');
    expect(sales.savedPhone, '0501234567');
    expect(sales.savedTrn, isNull);
    expect(sales.queue, hasLength(1));
    expect(sales.queue.single.type, 'customer_contact_update');
    expect(sales.remotePushed, isFalse);
    expect(selected?.phone, '0501234567');
    expect(find.byType(CustomerMissingFieldsDialog), findsNothing);
  });

  testWidgets('skip selects the customer without sending to Zoho',
      (tester) async {
    final resultFuture = await pumpDialog(
      tester,
      _customer(
        trn: '100533986400003',
        latitude: 25.1,
        longitude: 55.2,
      ),
    );

    await tester.enterText(find.byType(TextFormField), '0501234567');
    await tester.pump();

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    final selected = await resultFuture;

    expect(selected?.id, 'c1');
    expect(selected?.phone, '');
    expect(sales.savedPhone, isNull);
    expect(sales.remotePushed, isFalse);
  });
}
