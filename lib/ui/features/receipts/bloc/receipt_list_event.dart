import 'package:equatable/equatable.dart';

/// Base class for events handled by [ReceiptListBloc].
abstract class ReceiptListEvent extends Equatable {
  const ReceiptListEvent();

  @override
  List<Object?> get props => [];
}

/// Load receipt vouchers live-first for the active date filter.
class LoadReceipts extends ReceiptListEvent {
  const LoadReceipts();
}

/// Pull-to-refresh / app-bar refresh — same live-first path as [LoadReceipts].
class RefreshReceiptsFromZoho extends ReceiptListEvent {
  const RefreshReceiptsFromZoho();
}

/// Updates the list date range and reloads remote receipts for that range.
class SetReceiptDateFilter extends ReceiptListEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetReceiptDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Clears list error/success snackbar messages.
class ClearReceiptListMessages extends ReceiptListEvent {
  const ClearReceiptListMessages();
}
