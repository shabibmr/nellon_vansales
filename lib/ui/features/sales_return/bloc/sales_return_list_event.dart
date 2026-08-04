import 'package:equatable/equatable.dart';

/// Base class for events handled by [SalesReturnListBloc].
abstract class SalesReturnListEvent extends Equatable {
  const SalesReturnListEvent();

  @override
  List<Object?> get props => [];
}

/// Load sales returns live-first for the active date filter.
class LoadReturns extends SalesReturnListEvent {
  const LoadReturns();
}

/// Pull-to-refresh / app-bar refresh — same live-first path as [LoadReturns].
class RefreshReturnsFromZoho extends SalesReturnListEvent {
  const RefreshReturnsFromZoho();
}

/// Updates the list date range and reloads remote returns for that range.
class SetReturnDateFilter extends SalesReturnListEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetReturnDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Clears list error/success snackbar messages.
class ClearReturnListMessages extends SalesReturnListEvent {
  const ClearReturnListMessages();
}
