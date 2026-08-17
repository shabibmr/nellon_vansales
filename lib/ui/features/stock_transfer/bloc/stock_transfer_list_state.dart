import 'package:equatable/equatable.dart';

import '../../../../domain/models/stock_transfer.dart';
import '../../../core/bloc/list_load_status.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for Issue-to-Van / Stock-Unloading transfers.
class StockTransferListState extends Equatable {
  final StockTransferDirection direction;
  final List<StockTransfer> transfers;
  final DateTime? startDate;
  final DateTime? endDate;
  final ListLoadStatus status;
  final String? errorMessage;
  final String? successMessage;

  const StockTransferListState({
    this.direction = StockTransferDirection.load,
    this.transfers = const [],
    this.startDate,
    this.endDate,
    this.status = ListLoadStatus.initial,
    this.errorMessage,
    this.successMessage,
  });

  /// True while a remote list fetch is in flight.
  bool get isLoading => status == ListLoadStatus.loading;

  /// Transfers of [direction] filtered by the active date range.
  List<StockTransfer> get filteredTransfers => filterByDateRange(
    transfers.where((t) => t.direction == direction).toList(),
    (t) => t.date,
    startDate: startDate,
    endDate: endDate,
  );

  StockTransferListState copyWith({
    StockTransferDirection? direction,
    List<StockTransfer>? transfers,
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
    return StockTransferListState(
      direction: direction ?? this.direction,
      transfers: transfers ?? this.transfers,
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
    direction,
    transfers,
    startDate,
    endDate,
    status,
    errorMessage,
    successMessage,
  ];
}
