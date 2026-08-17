import 'package:equatable/equatable.dart';

import '../../../../domain/models/sales_return.dart';
import '../../../core/bloc/list_load_status.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for sales returns (filters, load status, messages).
class SalesReturnListState extends Equatable {
  final List<SalesReturn> returns;
  final DateTime? startDate;
  final DateTime? endDate;
  final ListLoadStatus status;
  final String? errorMessage;
  final String? successMessage;

  const SalesReturnListState({
    this.returns = const [],
    this.startDate,
    this.endDate,
    this.status = ListLoadStatus.initial,
    this.errorMessage,
    this.successMessage,
  });

  /// True while a remote list fetch is in flight.
  bool get isLoading => status == ListLoadStatus.loading;

  /// Returns filtered by the active date range.
  List<SalesReturn> get filteredReturns => filterByDateRange(
    returns,
    (r) => r.date,
    startDate: startDate,
    endDate: endDate,
  );

  SalesReturnListState copyWith({
    List<SalesReturn>? returns,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    ListLoadStatus? status,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    final nextStatus = status ??
        (isLoading == null
            ? this.status
            : (isLoading
                ? ListLoadStatus.loading
                : (errorMessage != null
                    ? ListLoadStatus.failure
                    : ListLoadStatus.success)));
    return SalesReturnListState(
      returns: returns ?? this.returns,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      status: nextStatus,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }

  @override
  List<Object?> get props => [
    returns,
    startDate,
    endDate,
    status,
    errorMessage,
    successMessage,
  ];
}
