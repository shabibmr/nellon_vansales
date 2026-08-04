// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/error_classification.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../core/utils/date_filter.dart';
import 'sales_order_list_event.dart';
import 'sales_order_list_state.dart';

/// Manages sales-order listing, date filtering, and live-first remote loads.
///
/// Concurrent loads (filter change while a refresh is in flight) are guarded
/// with a generation counter so only the latest request may emit results.
class SalesOrderListBloc
    extends Bloc<SalesOrderListEvent, SalesOrderListState> {
  final SalesRepository _salesRepository;

  /// Bumped on every remote list request; stale completions must not emit.
  int _fetchGeneration = 0;

  SalesOrderListBloc({required SalesRepository salesRepository})
    : _salesRepository = salesRepository,
      super(
        SalesOrderListState(
          startDate: todayDate(),
          endDate: todayDate(),
        ),
      ) {
    on<LoadSalesOrders>(_onLoadSalesOrders);
    on<RefreshSalesOrders>(_onRefreshSalesOrders);
    on<SetSalesOrderDateFilter>(_onSetDateFilter);
    on<ClearSalesOrderListMessages>(_onClearMessages);
  }

  /// Live-first load for [rangeStart]/[rangeEnd].
  ///
  /// When [applyDates] is true, the state dates are updated in the same emit
  /// as `isLoading: true` so the UI never shows a new range against a settled
  /// stale list.
  Future<void> _fetchOrders(
    Emitter<SalesOrderListState> emit, {
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
      final loaded = await _salesRepository.fetchRemoteOrders(
        startDate: rangeStart,
        endDate: rangeEnd,
      );
      if (generation != _fetchGeneration) return;
      emit(state.copyWith(orders: loaded, isLoading: false));
    } catch (e) {
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          orders: _salesRepository.getLocalOrders(),
          isLoading: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  Future<void> _onLoadSalesOrders(
    LoadSalesOrders event,
    Emitter<SalesOrderListState> emit,
  ) =>
      _fetchOrders(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onRefreshSalesOrders(
    RefreshSalesOrders event,
    Emitter<SalesOrderListState> emit,
  ) =>
      _fetchOrders(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onSetDateFilter(
    SetSalesOrderDateFilter event,
    Emitter<SalesOrderListState> emit,
  ) =>
      _fetchOrders(
        emit,
        rangeStart: event.startDate,
        rangeEnd: event.endDate,
        applyDates: true,
      );

  void _onClearMessages(
    ClearSalesOrderListMessages event,
    Emitter<SalesOrderListState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
