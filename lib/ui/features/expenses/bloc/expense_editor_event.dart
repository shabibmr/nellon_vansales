import 'dart:typed_data';
import 'package:equatable/equatable.dart';

import '../../../../domain/models/expense_entry.dart';

/// Base class for events handled by [ExpenseEditorBloc].
abstract class ExpenseEditorEvent extends Equatable {
  const ExpenseEditorEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a blank form for a new expense entry.
class StartNewExpense extends ExpenseEditorEvent {
  const StartNewExpense();
}

/// Opens an existing expense entry.
class OpenExpenseEntry extends ExpenseEditorEvent {
  final ExpenseEntry expense;

  const OpenExpenseEntry(this.expense);

  @override
  List<Object?> get props => [expense];
}

/// Re-attempts remote fetch for the expense held in editor state.
class RetryLoadExpenseEntry extends ExpenseEditorEvent {
  const RetryLoadExpenseEntry();
}

/// Updates expense date.
class SetEditingExpenseDate extends ExpenseEditorEvent {
  final DateTime date;

  const SetEditingExpenseDate(this.date);

  @override
  List<Object?> get props => [date];
}

/// Updates expense amount.
class SetEditingExpenseAmount extends ExpenseEditorEvent {
  final double amount;

  const SetEditingExpenseAmount(this.amount);

  @override
  List<Object?> get props => [amount];
}

/// Updates expense category.
class SetEditingExpenseCategory extends ExpenseEditorEvent {
  final String category;

  const SetEditingExpenseCategory(this.category);

  @override
  List<Object?> get props => [category];
}

/// Updates expense description.
class SetEditingExpenseDescription extends ExpenseEditorEvent {
  final String description;

  const SetEditingExpenseDescription(this.description);

  @override
  List<Object?> get props => [description];
}

/// Sets or clears receipt image attachment.
class SetReceiptImage extends ExpenseEditorEvent {
  final String? path;
  final Uint8List? bytes;

  const SetReceiptImage({this.path, this.bytes});

  @override
  List<Object?> get props => [path];
}

/// Saves the expense entry.
class SaveExpense extends ExpenseEditorEvent {
  const SaveExpense();
}

/// Clears editor error/success messages.
class ClearExpenseEditorMessages extends ExpenseEditorEvent {
  const ClearExpenseEditorMessages();
}
