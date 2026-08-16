// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/error_classification.dart';
import '../../../../domain/repositories/receipt_repository.dart';
import '../../../core/utils/date_filter.dart';
import 'receipt_list_event.dart';
import 'receipt_list_state.dart';

/// Manages receipt-voucher listing, date filtering, and live-first remote loads.
class ReceiptListBloc extends Bloc<ReceiptListEvent, ReceiptListState> {
  final ReceiptRepository _receiptRepository;

  /// Bumped on every remote list request; stale completions must not emit.
  int _fetchGeneration = 0;

  ReceiptListBloc({required ReceiptRepository receiptRepository})
    : _receiptRepository = receiptRepository,
      super(
        ReceiptListState(
          startDate: todayDate(),
          endDate: todayDate(),
        ),
      ) {
    on<LoadReceipts>(_onLoadReceipts);
    on<RefreshReceiptsFromZoho>(_onRefreshReceiptsFromZoho);
    on<SetReceiptDateFilter>(_onSetDateFilter);
    on<ClearReceiptListMessages>(_onClearMessages);
  }

  Future<void> _fetchReceipts(
    Emitter<ReceiptListState> emit, {
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
      final loaded = await _receiptRepository.fetchRemoteReceipts(
        startDate: rangeStart,
        endDate: rangeEnd,
      );
      if (generation != _fetchGeneration) return;
      emit(state.copyWith(receipts: loaded, isLoading: false));
    } catch (e) {
      if (generation != _fetchGeneration) return;
      emit(
        state.copyWith(
          receipts: _receiptRepository.getLocalReceipts(),
          isLoading: false,
          errorMessage: humanizeSyncError(e),
        ),
      );
    }
  }

  Future<void> _onLoadReceipts(
    LoadReceipts event,
    Emitter<ReceiptListState> emit,
  ) =>
      _fetchReceipts(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onRefreshReceiptsFromZoho(
    RefreshReceiptsFromZoho event,
    Emitter<ReceiptListState> emit,
  ) =>
      _fetchReceipts(
        emit,
        rangeStart: state.startDate,
        rangeEnd: state.endDate,
      );

  Future<void> _onSetDateFilter(
    SetReceiptDateFilter event,
    Emitter<ReceiptListState> emit,
  ) =>
      _fetchReceipts(
        emit,
        rangeStart: event.startDate,
        rangeEnd: event.endDate,
        applyDates: true,
      );

  void _onClearMessages(
    ClearReceiptListMessages event,
    Emitter<ReceiptListState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
