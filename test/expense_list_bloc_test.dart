import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/repositories/expense_repository.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_list_bloc.dart';
import 'package:van_sales/ui/features/expenses/bloc/expense_list_event.dart';

/// Minimal fake: expense list methods only; others noSuchMethod.
class FakeSalesRepository implements ExpenseRepository {
  List<ExpenseEntry> expenses = [];

  @override
  List<ExpenseEntry> getLocalExpenses() => List.of(expenses);

  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      List.of(expenses);

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) async {
    expenses.add(expense);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (invocation.isGetter) return null;
    if (name.contains('List') ||
        name.contains('getLocal') ||
        name.contains('getCustomers') ||
        name.contains('getItems') ||
        name.contains('getRoutes') ||
        name.contains('getSync') ||
        name.contains('getOpen') ||
        name.contains('getWarehouses')) {
      return <dynamic>[];
    }
    if (name.contains('hasPending')) return false;
    return Future<void>.value();
  }
}

void main() {
  late FakeSalesRepository salesRepo;
  late ExpenseListBloc bloc;

  setUp(() {
    salesRepo = FakeSalesRepository();
    bloc = ExpenseListBloc(expenseRepository: salesRepo);
  });

  tearDown(() async => bloc.close());

  test('LoadExpenses fetches remote expenses for active filter', () async {
    salesRepo.expenses = [
      ExpenseEntry(
        id: 'exp_1',
        date: DateTime.now(),
        lines: const [
          ExpenseLineItem(
            category: 'Fuel',
            amount: 75.0,
            description: 'Diesel',
          ),
        ],
      ),
    ];

    bloc.add(const LoadExpenses());
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.expenses, hasLength(1));
    expect(bloc.state.expenses.single.amount, 75.0);
  });
}
