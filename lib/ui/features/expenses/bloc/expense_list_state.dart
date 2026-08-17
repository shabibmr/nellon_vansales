import 'package:equatable/equatable.dart';

import '../../../../domain/models/expense_entry.dart';
import '../../../core/bloc/list_load_status.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for van expenses (filters, load status, messages).
class ExpenseListState extends Equatable {
  final List<ExpenseEntry> expenses;
  final DateTime? startDate;
  final DateTime? endDate;
  final ListLoadStatus status;
  final String? errorMessage;
  final String? successMessage;

  const ExpenseListState({
    this.expenses = const [],
    this.startDate,
    this.endDate,
    this.status = ListLoadStatus.initial,
    this.errorMessage,
    this.successMessage,
  });

  /// True while a remote list fetch is in flight.
  bool get isLoading => status == ListLoadStatus.loading;

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
    ListLoadStatus? status,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    final nextStatus = status ??
        (isLoading == null
            ? this.status
            : (isLoading
                ? ListLoadStatus.loading
                : (errorMessage != null
                    ? ListLoadStatus.failure
                    : ListLoadStatus.success)));
    return ExpenseListState(
      expenses: expenses ?? this.expenses,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      status: nextStatus,
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
    status,
    errorMessage,
    successMessage,
  ];
}
