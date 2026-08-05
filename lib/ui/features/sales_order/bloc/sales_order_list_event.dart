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

/// Reloads the list from the local cache only — no Zoho round-trip.
///
/// Used right after closing the editor: the save already wrote the edit to
/// the local cache synchronously, and the background sync push (fired
/// unawaited) hasn't necessarily reached Zoho yet. A live [LoadSalesOrders]
/// fetch at that instant can race the sync push and clobber the just-saved
/// edit — see `saveRemoteOrders` in `HiveDatabaseService`.
class ReloadSalesOrdersFromCache extends SalesOrderListEvent {
  const ReloadSalesOrdersFromCache();
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
