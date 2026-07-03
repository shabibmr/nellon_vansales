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

class SetEditingExpenseAmount extends ExpenseEvent {
  final double amount;
  const SetEditingExpenseAmount(this.amount);
  @override
  List<Object?> get props => [amount];
}

class SetEditingExpenseCategory extends ExpenseEvent {
  final String category;
  const SetEditingExpenseCategory(this.category);
  @override
  List<Object?> get props => [category];
}

class SetEditingExpenseDescription extends ExpenseEvent {
  final String description;
  const SetEditingExpenseDescription(this.description);
  @override
  List<Object?> get props => [description];
}

class SetReceiptImage extends ExpenseEvent {
  final String? path;
  final Uint8List? bytes;
  const SetReceiptImage({this.path, this.bytes});
  @override
  List<Object?> get props => [path];
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
  final double editingAmount;
  final String editingCategory;
  final String editingDescription;
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
    this.editingAmount = 0.0,
    this.editingCategory = 'Fuel',
    this.editingDescription = '',
    this.editingReceiptImagePath,
    this.editingReceiptImageBytes,
    this.isEditingNew = false,
  });

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
    double? editingAmount,
    String? editingCategory,
    String? editingDescription,
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
      successMessage: clearSuccess
          ? null
          : (successMessage ?? this.successMessage),
      editingId: editingId ?? this.editingId,
      editingDate: editingDate ?? this.editingDate,
      editingAmount: editingAmount ?? this.editingAmount,
      editingCategory: editingCategory ?? this.editingCategory,
      editingDescription: editingDescription ?? this.editingDescription,
      editingReceiptImagePath: clearReceiptImage
          ? null
          : (editingReceiptImagePath ?? this.editingReceiptImagePath),
      editingReceiptImageBytes: clearReceiptImage
          ? null
          : (editingReceiptImageBytes ?? this.editingReceiptImageBytes),
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
    editingAmount,
    editingCategory,
    editingDescription,
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
  }) : _salesRepository = salesRepository,
       _syncRepository = syncRepository,
       super(const ExpenseState()) {
    on<LoadExpenses>(_onLoadExpenses);
    on<SetExpenseDateFilter>(_onSetDateFilter);
    on<StartNewExpense>(_onStartNewExpense);
    on<StartEditExpense>(_onStartEditExpense);
    on<SetEditingExpenseDate>(_onSetEditingDate);
    on<SetEditingExpenseAmount>(_onSetEditingAmount);
    on<SetEditingExpenseCategory>(_onSetEditingCategory);
    on<SetEditingExpenseDescription>(_onSetEditingDescription);
    on<SetReceiptImage>(_onSetReceiptImage);
    on<SaveExpense>(_onSaveExpense);
    on<ClearExpenseMessages>(_onClearMessages);
  }

  Future<void> _onLoadExpenses(
    LoadExpenses event,
    Emitter<ExpenseState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final loaded = _salesRepository.getLocalExpenses();
      emit(state.copyWith(expenses: loaded, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSetDateFilter(
    SetExpenseDateFilter event,
    Emitter<ExpenseState> emit,
  ) {
    emit(state.copyWith(startDate: event.startDate, endDate: event.endDate));
  }

  void _onStartNewExpense(StartNewExpense event, Emitter<ExpenseState> emit) {
    emit(
      ExpenseState(
        expenses: state.expenses,
        startDate: state.startDate,
        endDate: state.endDate,
        editingId: 'temp_exp_${DateTime.now().millisecondsSinceEpoch}',
        editingDate: DateTime.now(),
        editingAmount: 0.0,
        editingCategory: 'Fuel',
        editingDescription: '',
        isEditingNew: true,
      ),
    );
  }

  void _onStartEditExpense(StartEditExpense event, Emitter<ExpenseState> emit) {
    final exp = event.expense;
    final firstLine = exp.lines.isNotEmpty ? exp.lines.first : null;
    emit(
      ExpenseState(
        expenses: state.expenses,
        startDate: state.startDate,
        endDate: state.endDate,
        editingId: exp.id,
        editingDate: exp.date,
        editingAmount: firstLine?.amount ?? exp.amount,
        editingCategory: firstLine?.category ?? 'Fuel',
        editingDescription: firstLine?.description ?? '',
        editingReceiptImagePath: exp.receiptImagePath,
        isEditingNew: false,
      ),
    );
  }

  void _onSetEditingDate(
    SetEditingExpenseDate event,
    Emitter<ExpenseState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onSetEditingAmount(
    SetEditingExpenseAmount event,
    Emitter<ExpenseState> emit,
  ) {
    emit(state.copyWith(editingAmount: event.amount));
  }

  void _onSetEditingCategory(
    SetEditingExpenseCategory event,
    Emitter<ExpenseState> emit,
  ) {
    emit(state.copyWith(editingCategory: event.category));
  }

  void _onSetEditingDescription(
    SetEditingExpenseDescription event,
    Emitter<ExpenseState> emit,
  ) {
    emit(state.copyWith(editingDescription: event.description));
  }

  void _onSetReceiptImage(SetReceiptImage event, Emitter<ExpenseState> emit) {
    if (event.path == null) {
      emit(state.copyWith(clearReceiptImage: true));
    } else {
      emit(
        state.copyWith(
          editingReceiptImagePath: event.path,
          editingReceiptImageBytes: event.bytes,
        ),
      );
    }
  }

  Future<void> _onSaveExpense(
    SaveExpense event,
    Emitter<ExpenseState> emit,
  ) async {
    if (state.editingAmount <= 0) {
      emit(state.copyWith(errorMessage: 'Please enter a valid amount'));
      return;
    }

    emit(state.copyWith(isLoading: true));
    try {
      final tempId =
          state.editingId ??
          'temp_exp_${DateTime.now().millisecondsSinceEpoch}';
      final line = ExpenseLineItem(
        category: state.editingCategory,
        amount: state.editingAmount,
        description: state.editingDescription,
      );
      final expense = ExpenseEntry(
        id: tempId,
        date: state.editingDate ?? DateTime.now(),
        lines: [line],
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
      emit(
        state.copyWith(
          expenses: updated,
          isLoading: false,
          successMessage: 'Expense saved successfully',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onClearMessages(
    ClearExpenseMessages event,
    Emitter<ExpenseState> emit,
  ) {
    emit(state.copyWith(clearError: true, clearSuccess: true));
  }
}
