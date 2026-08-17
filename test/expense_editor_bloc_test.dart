import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/repositories/expense_repository.dart';
import 'helpers/sales_repository_enqueue_stubs.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_editor_bloc.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_editor_event.dart';

class FakeSalesRepository
    with ExpenseRepositorySubmitStubs
    implements ExpenseRepository {
  List<ExpenseEntry> expenses = [];
  List<SyncQueueItem> queue = [];

  @override
  List<ExpenseEntry> getLocalExpenses() => List.of(expenses);

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    expenses.add(expense);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue.add(item);
  }

  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      expenses;

  @override
  Future<ExpenseEntry?> fetchExpenseById(String expenseId, {bool forceRemote = false, bool allowOfflineFallback = true}) async => null;
}

void main() {
  late FakeSalesRepository salesRepo;
  late ExpenseEditorBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    bloc = ExpenseEditorBloc(
      expenseRepository: salesRepo,
    );
  });

  tearDown(() async => bloc.close());

  test('StartNewExpense initializes form defaults', () async {
    bloc.add(const StartNewExpense());
    final state = await bloc.stream.firstWhere((s) => s.isEditingNew);

    expect(state.isEditingNew, isTrue);
    expect(state.editingCategory, 'Fuel');
    expect(state.editingAmount, 0.0);
  });

  test('SaveExpense submits without writing local history first', () async {
    bloc.add(const StartNewExpense());
    bloc.add(const SetEditingExpenseAmount(120.0));
    bloc.add(const SetEditingExpenseCategory('Maintenance'));
    bloc.add(const SetEditingExpenseDescription('Engine Oil'));
    bloc.add(const SaveExpense());

    await bloc.stream.firstWhere((s) => s.successMessage != null);

    expect(salesRepo.expenses, isEmpty);
    expect(salesRepo.queue, hasLength(1));
    expect(salesRepo.queue.single.type, 'expense');
    expect(bloc.state.successMessage, 'Saved to upload queue');
  });
}
