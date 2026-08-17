// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/error_classification.dart';
import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/repositories/stock_transfer_repository.dart';
import '../../../core/utils/date_filter.dart';
import 'stock_transfer_list_event.dart';
import 'stock_transfer_list_state.dart';

/// Manages Issue-to-Van / Stock-Unloading listing, date filtering, and
/// live-first remote loads.
class StockTransferListBloc
    extends Bloc<StockTransferListEvent, StockTransferListState> {
  final StockTransferRepository _stockTransferRepository;

  /// Bumped on every remote list request; stale completions must not emit.
  int _fetchGeneration = 0;

  StockTransferListBloc({
    required StockTransferRepository stockTransferRepository,
  }) : _stockTransferRepository = stockTransferRepository,
       super(
         StockTransferListState(
           startDate: todayDate(),
           endDate: todayDate(),
         ),
       ) {
    on<LoadStockTransfers>(_onLoadStockTransfers);
    on<RefreshStockTransfersFromZoho>(_onRefresh);
    on<SetStockTransferDateFilter>(_onSetDateFilter);
    on<ClearStockTransferListMessages>(_onClearMessages);
  }

  Future<void> _fetchTransfers(
    Emitter<StockTransferListState> emit, {
    required StockTransferDirection direction,
    required DateTime? rangeStart,
    required DateTime? rangeEnd,
    bool applyDates = false,
  }) async {
    final generation = ++_fetchGeneration;

    emit(
      state.copyWith(
        direction: direction,
        startDate: applyDates ? () => rangeStart : null,
        endDate: applyDates ? () => rangeEnd : null,
        isLoading: true,
        clearMessages: true,
      ),
    );

    try {
      final loaded = await _stockTransferRepository.fetchRemoteStockTransfers(
        startDate: rangeStart,
        endDate: rangeEnd,
        direction: direction,
      );
      if (generation != _fetchGeneration) return;
      emit(state.copyWith(transfers: loaded, isLoading: false));
    } catch (e) {
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          transfers: _stockTransferRepository
              .getLocalStockTransfers()
              .where((t) => t.direction == direction)
              .toList(),
          isLoading: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  Future<void> _onLoadStockTransfers(
    LoadStockTransfers event,
    Emitter<StockTransferListState> emit,
  ) =>
      _fetchTransfers(
        emit,
        direction: event.direction,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onRefresh(
    RefreshStockTransfersFromZoho event,
    Emitter<StockTransferListState> emit,
  ) =>
      _fetchTransfers(
        emit,
        direction: state.direction,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onSetDateFilter(
    SetStockTransferDateFilter event,
    Emitter<StockTransferListState> emit,
  ) =>
      _fetchTransfers(
        emit,
        direction: state.direction,
        rangeStart: event.startDate,
        rangeEnd: event.endDate,
        applyDates: true,
      );

  void _onClearMessages(
    ClearStockTransferListMessages event,
    Emitter<StockTransferListState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
