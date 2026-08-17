import 'package:equatable/equatable.dart';

import '../../../../domain/models/stock_transfer.dart';

/// Base class for events handled by [StockTransferListBloc].
abstract class StockTransferListEvent extends Equatable {
  const StockTransferListEvent();

  @override
  List<Object?> get props => [];
}

/// Load transfers live-first for [direction] and the active date filter.
class LoadStockTransfers extends StockTransferListEvent {
  final StockTransferDirection direction;

  const LoadStockTransfers(this.direction);

  @override
  List<Object?> get props => [direction];
}

/// Pull-to-refresh / app-bar refresh — same live-first path as [LoadStockTransfers].
class RefreshStockTransfersFromZoho extends StockTransferListEvent {
  const RefreshStockTransfersFromZoho();
}

/// Updates the list date range and reloads remote transfers for that range.
class SetStockTransferDateFilter extends StockTransferListEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetStockTransferDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Clears list error/success snackbar messages.
class ClearStockTransferListMessages extends StockTransferListEvent {
  const ClearStockTransferListMessages();
}
