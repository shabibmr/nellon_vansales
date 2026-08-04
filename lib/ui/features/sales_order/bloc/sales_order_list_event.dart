import 'package:equatable/equatable.dart';

/// Base class for events handled by [SalesOrderListBloc].
abstract class SalesOrderListEvent extends Equatable {
  const SalesOrderListEvent();

  @override
  List<Object?> get props => [];
}

/// Load sales orders live-first for the active date filter.
class LoadSalesOrders extends SalesOrderListEvent {
  const LoadSalesOrders();
}

/// Pull-to-refresh / app-bar refresh — same live-first path as [LoadSalesOrders].
class RefreshSalesOrders extends SalesOrderListEvent {
  const RefreshSalesOrders();
}

/// Updates the list date range and reloads remote orders for that range.
class SetSalesOrderDateFilter extends SalesOrderListEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetSalesOrderDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Clears list error/success snackbar messages.
class ClearSalesOrderListMessages extends SalesOrderListEvent {
  const ClearSalesOrderListMessages();
}
