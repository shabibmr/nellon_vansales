import 'package:equatable/equatable.dart';

import '../../../../domain/models/sales_return.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for sales returns (filters, load status, messages).
class SalesReturnListState extends Equatable {
  final List<SalesReturn> returns;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const SalesReturnListState({
    this.returns = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

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
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return SalesReturnListState(
      returns: returns ?? this.returns,
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
    returns,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
  ];
}
