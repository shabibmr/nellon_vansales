import 'package:equatable/equatable.dart';
import '../../../../domain/models/expense_entry.dart';

abstract class ExpenseLogState extends Equatable {
  const ExpenseLogState();

  @override
  List<Object?> get props => [];
}

class ExpenseLogInitial extends ExpenseLogState {}

class ExpenseLogSubmitting extends ExpenseLogState {}

class ExpenseLogSuccess extends ExpenseLogState {
  final ExpenseEntry expense;

  const ExpenseLogSuccess(this.expense);

  @override
  List<Object?> get props => [expense];
}

class ExpenseLogFailure extends ExpenseLogState {
  final String message;

  const ExpenseLogFailure(this.message);

  @override
  List<Object?> get props => [message];
}
