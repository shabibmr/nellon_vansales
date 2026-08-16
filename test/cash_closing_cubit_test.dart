import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/repositories/cash_closing_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/ui/features/dashboard/cubit/cash_closing_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/cash_closing_state.dart';

class FakeSalesRepository implements CashClosingRepository {
  CashClosing? savedCashClosing;
  List<SyncQueueItem> syncQueue = [];
  bool shouldThrow = false;

  @override
  CashClosing? getLocalCashClosing() => savedCashClosing;

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) async {
    if (shouldThrow) throw Exception('Cash closing save failed');
    savedCashClosing = closing;
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    if (shouldThrow) throw Exception('Queue enqueue failed');
    syncQueue.add(item);
  }

  @override
  bool hasPendingCashClosingForToday() => false;
}

class FakeSyncRepository implements SyncRepository {
  bool syncTriggered = false;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {
    syncTriggered = true;
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

void main() {
  late FakeSalesRepository salesRepo;
  late FakeSyncRepository syncRepo;
  late CashClosingCubit cubit;

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    cubit = CashClosingCubit(
      cashClosingRepository: salesRepo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() {
    cubit.close();
  });

  test('Initial state is CashClosingInitial', () {
    expect(cubit.state, isA<CashClosingInitial>());
  });

  test('submitCashClosing saves closing, enqueues sync, triggers sync, and emits CashClosingSuccess', () async {
    final expectedStates = [
      isA<CashClosingSubmitting>(),
      isA<CashClosingSuccess>(),
    ];

    expectLater(cubit.stream, emitsInOrder(expectedStates));

    await cubit.submitCashClosing(
      todaySales: 5000.0,
      todayPayments: 3000.0,
      todayExpenses: 200.0,
      physicalCashCounted: 3800.0, // Expected: 1000 + 3000 - 200 = 3800 => 0 diff
      notes: 'All balanced',
      openingBalance: 1000.0,
    );

    expect(salesRepo.savedCashClosing, isNotNull);
    final closing = salesRepo.savedCashClosing!;
    expect(closing.totalSalesInvoices, 5000.0);
    expect(closing.totalReceiptsCollected, 3000.0);
    expect(closing.totalExpenses, 200.0);
    expect(closing.closingBalance, 3800.0);
    expect(closing.reportedDifference, 0.0);
    expect(closing.notes, 'All balanced');

    expect(salesRepo.syncQueue.length, 1);
    expect(salesRepo.syncQueue.first.type, 'expense');

    expect(syncRepo.syncTriggered, true);
  });

  test('submitCashClosing handles exception and emits CashClosingFailure', () async {
    salesRepo.shouldThrow = true;

    final expectedStates = [
      isA<CashClosingSubmitting>(),
      isA<CashClosingFailure>(),
    ];

    expectLater(cubit.stream, emitsInOrder(expectedStates));

    await cubit.submitCashClosing(
      todaySales: 1000.0,
      todayPayments: 500.0,
      todayExpenses: 50.0,
      physicalCashCounted: 1450.0,
      notes: 'Failed test',
      openingBalance: 0,
    );

    final state = cubit.state;
    expect(state, isA<CashClosingFailure>());
    expect((state as CashClosingFailure).message, contains('Cash closing save failed'));
  });
}
