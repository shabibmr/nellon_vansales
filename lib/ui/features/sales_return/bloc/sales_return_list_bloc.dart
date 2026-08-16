// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/error_classification.dart';
import '../../../../domain/repositories/sales_return_repository.dart';
import '../../../core/utils/date_filter.dart';
import 'sales_return_list_event.dart';
import 'sales_return_list_state.dart';

/// Manages sales-return listing, date filtering, and live-first remote loads.
class SalesReturnListBloc
    extends Bloc<SalesReturnListEvent, SalesReturnListState> {
  final SalesReturnRepository _salesReturnRepository;

  /// Bumped on every remote list request; stale completions must not emit.
  int _fetchGeneration = 0;

  SalesReturnListBloc({required SalesReturnRepository salesReturnRepository})
    : _salesReturnRepository = salesReturnRepository,
      super(
        SalesReturnListState(
          startDate: todayDate(),
          endDate: todayDate(),
        ),
      ) {
    on<LoadReturns>(_onLoadReturns);
    on<RefreshReturnsFromZoho>(_onRefreshReturnsFromZoho);
    on<SetReturnDateFilter>(_onSetDateFilter);
    on<ClearReturnListMessages>(_onClearMessages);
  }

  Future<void> _fetchReturns(
    Emitter<SalesReturnListState> emit, {
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
      final loaded = await _salesReturnRepository.fetchRemoteReturns(
        startDate: rangeStart,
        endDate: rangeEnd,
      );
      if (generation != _fetchGeneration) return;
      emit(state.copyWith(returns: loaded, isLoading: false));
    } catch (e) {
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          returns: _salesReturnRepository.getLocalReturns(),
          isLoading: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  Future<void> _onLoadReturns(
    LoadReturns event,
    Emitter<SalesReturnListState> emit,
  ) =>
      _fetchReturns(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onRefreshReturnsFromZoho(
    RefreshReturnsFromZoho event,
    Emitter<SalesReturnListState> emit,
  ) =>
      _fetchReturns(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onSetDateFilter(
    SetReturnDateFilter event,
    Emitter<SalesReturnListState> emit,
  ) =>
      _fetchReturns(
        emit,
        rangeStart: event.startDate,
        rangeEnd: event.endDate,
        applyDates: true,
      );

  void _onClearMessages(
    ClearReturnListMessages event,
    Emitter<SalesReturnListState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
