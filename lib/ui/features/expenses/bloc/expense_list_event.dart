import 'package:equatable/equatable.dart';

/// Base class for events handled by [ExpenseListBloc].
abstract class ExpenseListEvent extends Equatable {
  const ExpenseListEvent();

  @override
  List<Object?> get props => [];
}

/// Load expenses live-first for the active date filter.
class LoadExpenses extends ExpenseListEvent {
  const LoadExpenses();
}

/// Pull-to-refresh / app-bar refresh — same live-first path as [LoadExpenses].
class RefreshExpensesFromZoho extends ExpenseListEvent {
  const RefreshExpensesFromZoho();
}

/// Updates the list date range and reloads remote expenses for that range.
class SetExpenseDateFilter extends ExpenseListEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetExpenseDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Clears list error/success snackbar messages.
class ClearExpenseListMessages extends ExpenseListEvent {
  const ClearExpenseListMessages();
}
