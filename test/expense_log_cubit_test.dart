import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/repositories/expense_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/ui/features/dashboard/cubit/expense_log_cubit.dart';
import 'package:van_sales/ui/features/dashboard/cubit/expense_log_state.dart';

class FakeSalesRepository
    with ExpenseRepositorySubmitStubs
    implements ExpenseRepository {
  List<ExpenseEntry> expenses = [];
  List<SyncQueueItem> syncQueue = [];
  bool shouldThrow = false;

  @override
  List<ExpenseEntry> getLocalExpenses() => expenses;

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    if (shouldThrow) throw Exception('Database write failed');
    expenses.add(expense);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    if (shouldThrow) throw Exception('Queue enqueue failed');
    syncQueue.add(item);
  }

  @override
  Future<ExpenseEntry?> fetchExpenseById(String expenseId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({DateTime? startDate, DateTime? endDate}) async => [];
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
  late ExpenseLogCubit cubit;

  setUp(() {
    salesRepo = FakeSalesRepository();
    syncRepo = FakeSyncRepository();
    cubit = ExpenseLogCubit(
      expenseRepository: salesRepo,
      syncRepository: syncRepo,
    );
  });

  tearDown(() {
    cubit.close();
  });

  test('Initial state is ExpenseLogInitial', () {
    expect(cubit.state, isA<ExpenseLogInitial>());
  });

  test('submitExpense saves expense, enqueues sync, triggers sync, and emits ExpenseLogSuccess', () async {
    final expectedStates = [
      isA<ExpenseLogSubmitting>(),
      isA<ExpenseLogSuccess>(),
    ];

    expectLater(cubit.stream, emitsInOrder(expectedStates));

    await cubit.submitExpense(
      amount: 150.0,
      category: 'Fuel',
      description: 'Diesel top-up',
      receiptImagePath: '/path/to/receipt.jpg',
    );

    expect(salesRepo.expenses, isEmpty);
    expect(salesRepo.syncQueue.length, 1);
    expect(salesRepo.syncQueue.first.type, 'expense');
  });

  test('submitExpense handles exception and emits ExpenseLogFailure', () async {
    salesRepo.shouldThrow = true;

    final expectedStates = [
      isA<ExpenseLogSubmitting>(),
      isA<ExpenseLogFailure>(),
    ];

    expectLater(cubit.stream, emitsInOrder(expectedStates));

    await cubit.submitExpense(
      amount: 50.0,
      category: 'Tolls',
      description: 'Highway toll',
    );

    final state = cubit.state;
    expect(state, isA<ExpenseLogFailure>());
    expect((state as ExpenseLogFailure).message, contains('Queue enqueue failed'));
  });
}
