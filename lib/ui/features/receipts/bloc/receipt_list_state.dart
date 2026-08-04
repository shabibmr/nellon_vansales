import 'package:equatable/equatable.dart';

import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for receipt vouchers (filters, load status, messages).
class ReceiptListState extends Equatable {
  final List<ReceiptVoucher> receipts;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const ReceiptListState({
    this.receipts = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

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
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return ReceiptListState(
      receipts: receipts ?? this.receipts,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      isLoading: isLoading ?? this.isLoading,
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
    isLoading,
    errorMessage,
    successMessage,
  ];
}
