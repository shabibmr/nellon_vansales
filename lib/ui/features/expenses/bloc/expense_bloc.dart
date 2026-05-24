import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/models/sync_queue_item.dart';

// --- Events ---

abstract class ExpenseEvent extends Equatable {
  const ExpenseEvent();
  @override
  List<Object?> get props => [];
}

class LoadExpenses extends ExpenseEvent {}

class SetExpenseDateFilter extends ExpenseEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const SetExpenseDateFilter({this.startDate, this.endDate});
  @override
  List<Object?> get props => [startDate, endDate];
}

class StartNewExpense extends ExpenseEvent {}

class StartEditExpense extends ExpenseEvent {
  final ExpenseEntry expense;
  const StartEditExpense(this.expense);
  @override
  List<Object?> get props => [expense];
}

class SetEditingExpenseDate extends ExpenseEvent {
  final DateTime date;
  const SetEditingExpenseDate(this.date);
  @override
  List<Object?> get props => [date];
}

class SetReceiptImage extends ExpenseEvent {
  final String? path;
  final Uint8List? bytes;
  const SetReceiptImage({this.path, this.bytes});
  @override
  List<Object?> get props => [path];
}

class AddExpenseLine extends ExpenseEvent {
  final ExpenseLineItem line;
  const AddExpenseLine(this.line);
  @override
  List<Object?> get props => [line];
}

class UpdateExpenseLine extends ExpenseEvent {
  final int index;
  final ExpenseLineItem line;
  const UpdateExpenseLine(this.index, this.line);
  @override
  List<Object?> get props => [index, line];
}

class RemoveExpenseLine extends ExpenseEvent {
  final int index;
  const RemoveExpenseLine(this.index);
  @override
  List<Object?> get props => [index];
}

class SaveExpense extends ExpenseEvent {}

class ClearExpenseMessages extends ExpenseEvent {}

// --- State ---

class ExpenseState extends Equatable {
  final List<ExpenseEntry> expenses;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  // Editor fields
  final String? editingId;
  final DateTime? editingDate;
  final List<ExpenseLineItem> editingLines;
  final String? editingReceiptImagePath;
  final Uint8List? editingReceiptImageBytes;
  final bool isEditingNew;

  const ExpenseState({
    this.expenses = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.editingId,
    this.editingDate,
    this.editingLines = const [],
    this.editingReceiptImagePath,
    this.editingReceiptImageBytes,
    this.isEditingNew = false,
  });

  double get editingTotal => editingLines.fold(0.0, (sum, l) => sum + l.amount);

  List<ExpenseEntry> get filteredExpenses {
    return expenses.where((exp) {
      final day = DateTime(exp.date.year, exp.date.month, exp.date.day);
      if (startDate != null) {
        final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
        if (day.isBefore(s)) return false;
      }
      if (endDate != null) {
        final e = DateTime(endDate!.year, endDate!.month, endDate!.day);
        if (day.isAfter(e)) return false;
      }
      return true;
    }).toList();
  }

  ExpenseState copyWith({
    List<ExpenseEntry>? expenses,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    String? editingId,
    DateTime? editingDate,
    List<ExpenseLineItem>? editingLines,
    String? editingReceiptImagePath,
    Uint8List? editingReceiptImageBytes,
    bool? isEditingNew,
    bool clearReceiptImage = false,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return ExpenseState(
      expenses: expenses ?? this.expenses,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
      editingId: editingId ?? this.editingId,
      editingDate: editingDate ?? this.editingDate,
      editingLines: editingLines ?? this.editingLines,
      editingReceiptImagePath: clearReceiptImage ? null : (editingReceiptImagePath ?? this.editingReceiptImagePath),
      editingReceiptImageBytes: clearReceiptImage ? null : (editingReceiptImageBytes ?? this.editingReceiptImageBytes),
      isEditingNew: isEditingNew ?? this.isEditingNew,
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
        editingId,
        editingDate,
        editingLines,
        editingReceiptImagePath,
        isEditingNew,
      ];
}

// --- Bloc ---

class ExpenseBloc extends Bloc<ExpenseEvent, ExpenseState> {
  final SalesRepository _salesRepository;
  final SyncRepository _syncRepository;

  ExpenseBloc({
    required SalesRepository salesRepository,
    required SyncRepository syncRepository,
  })  : _salesRepository = salesRepository,
        _syncRepository = syncRepository,
        super(const ExpenseState()) {
    on<LoadExpenses>(_onLoadExpenses);
    on<SetExpenseDateFilter>(_onSetDateFilter);
    on<StartNewExpense>(_onStartNewExpense);
    on<StartEditExpense>(_onStartEditExpense);
    on<SetEditingExpenseDate>(_onSetEditingDate);
    on<SetReceiptImage>(_onSetReceiptImage);
    on<AddExpenseLine>(_onAddExpenseLine);
    on<UpdateExpenseLine>(_onUpdateExpenseLine);
    on<RemoveExpenseLine>(_onRemoveExpenseLine);
    on<SaveExpense>(_onSaveExpense);
    on<ClearExpenseMessages>(_onClearMessages);
  }

  Future<void> _onLoadExpenses(LoadExpenses event, Emitter<ExpenseState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = _salesRepository.getLocalExpenses();
      emit(state.copyWith(expenses: loaded, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSetDateFilter(SetExpenseDateFilter event, Emitter<ExpenseState> emit) {
    emit(state.copyWith(startDate: event.startDate, endDate: event.endDate));
  }

  void _onStartNewExpense(StartNewExpense event, Emitter<ExpenseState> emit) {
    emit(ExpenseState(
      expenses: state.expenses,
      startDate: state.startDate,
      endDate: state.endDate,
      editingId: 'temp_exp_${DateTime.now().millisecondsSinceEpoch}',
      editingDate: DateTime.now(),
      editingLines: const [],
      isEditingNew: true,
    ));
  }

  void _onStartEditExpense(StartEditExpense event, Emitter<ExpenseState> emit) {
    final exp = event.expense;
    emit(ExpenseState(
      expenses: state.expenses,
      startDate: state.startDate,
      endDate: state.endDate,
      editingId: exp.id,
      editingDate: exp.date,
      editingLines: List.from(exp.lines),
      editingReceiptImagePath: exp.receiptImagePath,
      isEditingNew: false,
    ));
  }

  void _onSetEditingDate(SetEditingExpenseDate event, Emitter<ExpenseState> emit) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onSetReceiptImage(SetReceiptImage event, Emitter<ExpenseState> emit) {
    if (event.path == null) {
      emit(state.copyWith(clearReceiptImage: true));
    } else {
      emit(state.copyWith(
        editingReceiptImagePath: event.path,
        editingReceiptImageBytes: event.bytes,
      ));
    }
  }

  void _onAddExpenseLine(AddExpenseLine event, Emitter<ExpenseState> emit) {
    final lines = List<ExpenseLineItem>.from(state.editingLines)..add(event.line);
    emit(state.copyWith(editingLines: lines, clearError: true));
  }

  void _onUpdateExpenseLine(UpdateExpenseLine event, Emitter<ExpenseState> emit) {
    final lines = List<ExpenseLineItem>.from(state.editingLines);
    if (event.index >= 0 && event.index < lines.length) {
      lines[event.index] = event.line;
    }
    emit(state.copyWith(editingLines: lines));
  }

  void _onRemoveExpenseLine(RemoveExpenseLine event, Emitter<ExpenseState> emit) {
    final lines = List<ExpenseLineItem>.from(state.editingLines);
    if (event.index >= 0 && event.index < lines.length) {
      lines.removeAt(event.index);
    }
    emit(state.copyWith(editingLines: lines));
  }

  Future<void> _onSaveExpense(SaveExpense event, Emitter<ExpenseState> emit) async {
    if (state.editingLines.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please add at least one expense line'));
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final tempId = state.editingId ?? 'temp_exp_${DateTime.now().millisecondsSinceEpoch}';
      final expense = ExpenseEntry(
        id: tempId,
        date: state.editingDate ?? DateTime.now(),
        lines: state.editingLines,
        receiptImagePath: state.editingReceiptImagePath,
        isPendingSync: true,
      );

      await _salesRepository.saveLocalExpense(expense);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'expense',
        payload: ExpenseEntryModel.fromDomain(expense).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _salesRepository.enqueueSyncItem(syncItem);

      _syncRepository.triggerSync();

      final updated = _salesRepository.getLocalExpenses();
      emit(state.copyWith(
        expenses: updated,
        isLoading: false,
        successMessage: 'Expense saved successfully',
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onClearMessages(ClearExpenseMessages event, Emitter<ExpenseState> emit) {
    emit(state.copyWith(clearError: true, clearSuccess: true));
  }
}
