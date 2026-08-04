import 'package:equatable/equatable.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for sales orders (filters, load status, messages).
class SalesOrderListState extends Equatable {
  final List<SalesOrder> orders;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const SalesOrderListState({
    this.orders = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  /// Orders filtered by the active date range (client-side safety net).
  List<SalesOrder> get filteredOrders => filterByDateRange(
    orders,
    (ord) => ord.date,
    startDate: startDate,
    endDate: endDate,
  );

  /// [clearMessages] nulls error/success (plain `null` args cannot clear them).
  SalesOrderListState copyWith({
    List<SalesOrder>? orders,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return SalesOrderListState(
      orders: orders ?? this.orders,
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
    orders,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
  ];
}
