import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/date_filter.dart';
import 'report_event.dart';
import 'report_state.dart';

class ReportBloc<T> extends Bloc<ReportEvent, ReportState<T>> {
  final List<T> Function() getLocal;
  final Future<List<T>> Function() fetchRemote;

  bool _isFetching = false;

  ReportBloc({
    required this.getLocal,
    required this.fetchRemote,
    Object? initialSortField,
    bool initialSortAscending = true,
  }) : super(ReportState<T>(
          isLoading: true,
          rows: getLocal(),
          // Default filter to today so reports open scoped to the current day.
          startDate: todayDate(),
          endDate: todayDate(),
          sortField: initialSortField,
          sortAscending: initialSortAscending,
        )) {
    on<RefreshReport>(_onRefreshReport);
    on<SetDateRange>(_onSetDateRange);
    on<SetSort>(_onSetSort);

    // Run initial load
    add(const RefreshReport());
  }

  Future<void> _onRefreshReport(
    RefreshReport event,
    Emitter<ReportState<T>> emit,
  ) async {
    if (_isFetching) return;
    _isFetching = true;

    emit(state.copyWith(isLoading: true, error: () => null));
    try {
      final remoteRows = await fetchRemote();
      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        rows: remoteRows,
        isLiveData: true,
        error: () => null,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        isLiveData: false,
        error: () => e.toString(),
      ));
    } finally {
      _isFetching = false;
    }
  }

  void _onSetDateRange(
    SetDateRange event,
    Emitter<ReportState<T>> emit,
  ) {
    emit(state.copyWith(
      startDate: () => event.startDate,
      endDate: () => event.endDate,
    ));
  }

  void _onSetSort(
    SetSort event,
    Emitter<ReportState<T>> emit,
  ) {
    if (state.sortField == event.field) {
      emit(state.copyWith(
        sortAscending: event.ascending ?? !state.sortAscending,
      ));
    } else {
      emit(state.copyWith(
        sortField: () => event.field,
        sortAscending: event.ascending ?? true,
      ));
    }
  }
}
