// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/error_classification.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../core/utils/date_filter.dart';
import 'expense_list_event.dart';
import 'expense_list_state.dart';

/// Manages van-expense listing, date filtering, and live-first remote loads.
class ExpenseListBloc extends Bloc<ExpenseListEvent, ExpenseListState> {
  final SalesRepository _salesRepository;

  /// Bumped on every remote list request; stale completions must not emit.
  int _fetchGeneration = 0;

  ExpenseListBloc({required SalesRepository salesRepository})
    : _salesRepository = salesRepository,
      super(
        ExpenseListState(
          startDate: todayDate(),
          endDate: todayDate(),
        ),
      ) {
    on<LoadExpenses>(_onLoadExpenses);
    on<RefreshExpensesFromZoho>(_onRefreshExpensesFromZoho);
    on<SetExpenseDateFilter>(_onSetDateFilter);
    on<ClearExpenseListMessages>(_onClearMessages);
  }

  Future<void> _fetchExpenses(
    Emitter<ExpenseListState> emit, {
    required DateTime? rangeStart,
    required DateTime? rangeEnd,
    bool applyDates = false,
  }) async {
    final generation = ++_fetchGeneration;

    emit(
      state.copyWith(
        startDate: applyDates ? () => rangeStart : null,
        endDate: applyDates ? () => rangeEnd : null,
        isLoading: true,
        clearMessages: true,
      ),
    );

    try {
      final loaded = await _salesRepository.fetchRemoteExpenses(
        startDate: rangeStart,
        endDate: rangeEnd,
      );
      if (generation != _fetchGeneration) return;
      emit(state.copyWith(expenses: loaded, isLoading: false));
    } catch (e) {
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          expenses: _salesRepository.getLocalExpenses(),
          isLoading: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  Future<void> _onLoadExpenses(
    LoadExpenses event,
    Emitter<ExpenseListState> emit,
  ) =>
      _fetchExpenses(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onRefreshExpensesFromZoho(
    RefreshExpensesFromZoho event,
    Emitter<ExpenseListState> emit,
  ) =>
      _fetchExpenses(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onSetDateFilter(
    SetExpenseDateFilter event,
    Emitter<ExpenseListState> emit,
  ) =>
      _fetchExpenses(
        emit,
        rangeStart: event.startDate,
        rangeEnd: event.endDate,
        applyDates: true,
      );

  void _onClearMessages(
    ClearExpenseListMessages event,
    Emitter<ExpenseListState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
