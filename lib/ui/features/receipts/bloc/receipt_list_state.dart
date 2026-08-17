import 'package:equatable/equatable.dart';

import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/bloc/list_load_status.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for receipt vouchers (filters, load status, messages).
class ReceiptListState extends Equatable {
  final List<ReceiptVoucher> receipts;
  final DateTime? startDate;
  final DateTime? endDate;
  final ListLoadStatus status;
  final String? errorMessage;
  final String? successMessage;

  const ReceiptListState({
    this.receipts = const [],
    this.startDate,
    this.endDate,
    this.status = ListLoadStatus.initial,
    this.errorMessage,
    this.successMessage,
  });

  /// True while a remote list fetch is in flight.
  bool get isLoading => status == ListLoadStatus.loading;

  /// Receipts filtered by the active date range.
  List<ReceiptVoucher> get filteredReceipts => filterByDateRange(
    receipts,
    (rec) => rec.date,
    startDate: startDate,
    endDate: endDate,
  );

  ReceiptListState copyWith({
    List<ReceiptVoucher>? receipts,
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
    return ReceiptListState(
      receipts: receipts ?? this.receipts,
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
    receipts,
    startDate,
    endDate,
    status,
    errorMessage,
    successMessage,
  ];
}
