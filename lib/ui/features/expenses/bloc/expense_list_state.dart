import 'package:equatable/equatable.dart';

import '../../../../domain/models/expense_entry.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for van expenses (filters, load status, messages).
class ExpenseListState extends Equatable {
  final List<ExpenseEntry> expenses;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const ExpenseListState({
    this.expenses = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  /// Expenses filtered by the active date range.
  List<ExpenseEntry> get filteredExpenses => filterByDateRange(
    expenses,
    (exp) => exp.date,
    startDate: startDate,
    endDate: endDate,
  );

  ExpenseListState copyWith({
    List<ExpenseEntry>? expenses,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return ExpenseListState(
      expenses: expenses ?? this.expenses,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }

  @override
  List<Object?> get props => [
    expenses,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
  ];
}
