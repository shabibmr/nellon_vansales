// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/repositories/expense_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../domain/utils/voucher_content_fingerprint.dart';
import 'expense_editor_event.dart';
import 'expense_editor_state.dart';

/// Manages a single expense form: open, edit fields, save, enqueue sync.
class ExpenseEditorBloc
    extends Bloc<ExpenseEditorEvent, ExpenseEditorState> {
  final ExpenseRepository _expenseRepository;
  final SyncRepository _syncRepository;

  ExpenseEditorBloc({
    required ExpenseRepository expenseRepository,
    required SyncRepository syncRepository,
  }) : _expenseRepository = expenseRepository,
       _syncRepository = syncRepository,
       super(const ExpenseEditorState()) {
    on<StartNewExpense>(_onStartNewExpense);
    on<OpenExpenseEntry>(_onOpenExpenseEntry);
    on<RetryLoadExpenseEntry>(_onRetryLoadExpenseEntry);
    on<RefreshExpenseEntryFromZoho>(_onRefreshExpenseEntryFromZoho);
    on<SetEditingExpenseDate>(_onSetEditingDate);
    on<SetEditingExpenseAmount>(_onSetEditingAmount);
    on<SetEditingExpenseCategory>(_onSetEditingCategory);
    on<SetEditingExpenseDescription>(_onSetEditingDescription);
    on<SetReceiptImage>(_onSetReceiptImage);
    on<SaveExpense>(_onSaveExpense);
    on<ClearExpenseEditorMessages>(_onClearMessages);
  }

  static bool _isLocalExpenseId(String id) => id.startsWith('temp_exp_');

  void _onStartNewExpense(
    StartNewExpense event,
    Emitter<ExpenseEditorState> emit,
  ) {
    final now = DateTime.now();
    emit(
      state.copyWith(
        clearEditingId: true,
        clearMessages: true,
        editingDate: now,
        editingAmount: 0.0,
        editingCategory: 'Fuel',
        editingDescription: '',
        clearReceiptImage: true,
        isEditingNew: true,
        isEditorLoading: false,
        isSaving: false,
        clearEditorError: true,
      ),
    );
  }

  Future<void> _onOpenExpenseEntry(
    OpenExpenseEntry event,
    Emitter<ExpenseEditorState> emit,
  ) async {
    if (event.expense.isPendingSync || _isLocalExpenseId(event.expense.id)) {
      emit(_openedFrom(event.expense));
      return;
    }

    emit(
      state.copyWith(
        editingId: event.expense.id,
        clearEditingExpense: true,
        clearMessages: true,
        clearEditorError: true,
        isEditingNew: false,
        isEditorLoading: true,
        isSaving: false,
      ),
    );
    await _loadEditingExpenseFromZoho(event.expense.id, emit);
  }

  Future<void> _onRetryLoadExpenseEntry(
    RetryLoadExpenseEntry event,
    Emitter<ExpenseEditorState> emit,
  ) async {
    final expenseId = state.editingId;
    if (expenseId == null || expenseId.isEmpty) return;
    emit(state.copyWith(isEditorLoading: true, clearEditorError: true));
    await _loadEditingExpenseFromZoho(expenseId, emit);
  }

  Future<void> _onRefreshExpenseEntryFromZoho(
    RefreshExpenseEntryFromZoho event,
    Emitter<ExpenseEditorState> emit,
  ) async {
    final expenseId = state.editingId ?? state.editingExpense?.id;
    if (expenseId == null ||
        expenseId.isEmpty ||
        _isLocalExpenseId(expenseId) ||
        state.isEditorLoading ||
        state.isRefreshing ||
        state.editingExpense == null) {
      return;
    }
    emit(
      state.copyWith(
        isRefreshing: true,
        clearEditorError: true,
        clearMessages: true,
      ),
    );
    await _loadEditingExpenseFromZoho(expenseId, emit, isRefresh: true);
  }

  Future<void> _loadEditingExpenseFromZoho(
    String expenseId,
    Emitter<ExpenseEditorState> emit, {
    bool isRefresh = false,
  }) async {
    final previous = isRefresh ? state.editingExpense : null;
    final wasDirty = isRefresh && state.isFormDirty;

    ExpenseEntry? fetched;
    try {
      fetched = await _expenseRepository.fetchExpenseById(
        expenseId,
        forceRemote: true,
        allowOfflineFallback: false,
      );
    } catch (e) {
      if (isRefresh) {
        emit(
          state.copyWith(
            isRefreshing: false,
            errorMessage: humanizeSyncError(e),
          ),
        );
        return;
      }
      try {
        fetched = await _expenseRepository.fetchExpenseById(
          expenseId,
          forceRemote: false,
        );
      } catch (_) {
        fetched = null;
      }
      if (fetched != null) {
        emit(
          _openedFrom(fetched).copyWith(
            infoMessage: 'Showing offline copy',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          isEditorLoading: false,
          isRefreshing: false,
          editorError: humanizeSyncError(e),
        ),
      );
      return;
    }

    if (fetched == null) {
      if (!isRefresh) {
        ExpenseEntry? local;
        try {
          local = await _expenseRepository.fetchExpenseById(
            expenseId,
            forceRemote: false,
          );
        } catch (_) {
          local = null;
        }
        if (local != null) {
          emit(
            _openedFrom(local).copyWith(
              infoMessage: 'Not found in Zoho — showing local copy',
            ),
          );
          return;
        }
      }
      if (isRefresh && previous != null) {
        emit(
          state.copyWith(
            isRefreshing: false,
            errorMessage: 'This expense entry was not found in Zoho Books.',
          ),
        );
      } else {
        emit(
          state.copyWith(
            isEditorLoading: false,
            isRefreshing: false,
            editorError: 'This expense entry was not found in Zoho Books.',
          ),
        );
      }
      return;
    }

    final opened = _openedFrom(fetched);
    if (isRefresh) {
      final contentUnchanged = previous != null &&
          VoucherContentFingerprint.expense(previous) ==
              VoucherContentFingerprint.expense(fetched);
      emit(
        opened.copyWith(
          isRefreshing: false,
          infoMessage: (wasDirty || !contentUnchanged)
              ? 'Updated from Zoho Books'
              : 'Already up to date',
        ),
      );
    } else {
      emit(opened);
    }
  }

  ExpenseEditorState _openedFrom(ExpenseEntry exp) {
    final firstLine = exp.lines.isNotEmpty ? exp.lines.first : null;

    return state.copyWith(
      editingId: exp.id,
      editingExpense: exp.copyWith(),
      editingDate: exp.date,
      editingAmount: firstLine?.amount ?? exp.amount,
      editingCategory: firstLine?.category ?? 'Fuel',
      editingDescription: firstLine?.description ?? '',
      editingReceiptImagePath: exp.receiptImagePath,
      isEditingNew: false,
      isEditorLoading: false,
      isSaving: false,
      clearMessages: true,
      clearEditorError: true,
    );
  }

  void _onSetEditingDate(
    SetEditingExpenseDate event,
    Emitter<ExpenseEditorState> emit,
  ) {
    emit(state.copyWith(editingDate: event.date));
  }

  void _onSetEditingAmount(
    SetEditingExpenseAmount event,
    Emitter<ExpenseEditorState> emit,
  ) {
    emit(state.copyWith(editingAmount: event.amount));
  }

  void _onSetEditingCategory(
    SetEditingExpenseCategory event,
    Emitter<ExpenseEditorState> emit,
  ) {
    emit(state.copyWith(editingCategory: event.category));
  }

  void _onSetEditingDescription(
    SetEditingExpenseDescription event,
    Emitter<ExpenseEditorState> emit,
  ) {
    emit(state.copyWith(editingDescription: event.description));
  }

  void _onSetReceiptImage(
    SetReceiptImage event,
    Emitter<ExpenseEditorState> emit,
  ) {
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
    Emitter<ExpenseEditorState> emit,
  ) async {
    if (state.editingAmount <= 0) {
      emit(state.copyWith(errorMessage: 'Please enter a valid amount'));
      return;
    }

    emit(state.copyWith(isSaving: true, clearMessages: true));
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

      await _expenseRepository.saveLocalExpense(expense);

      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'expense',
        payload: ExpenseEntryModel.fromDomain(expense).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await _expenseRepository.enqueueSyncItem(syncItem);

      unawaited(_syncRepository.triggerSync());

      emit(
        state.copyWith(
          editingId: expense.id,
          editingExpense: expense,
          isEditingNew: false,
          isSaving: false,
          successMessage: 'Expense saved successfully',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  void _onClearMessages(
    ClearExpenseEditorMessages event,
    Emitter<ExpenseEditorState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
