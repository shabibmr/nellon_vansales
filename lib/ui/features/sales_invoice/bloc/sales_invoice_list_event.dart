import 'package:equatable/equatable.dart';
import '../../../../domain/models/sales_order.dart';

/// Base class for events handled by [SalesInvoiceListBloc].
abstract class SalesInvoiceListEvent extends Equatable {
  const SalesInvoiceListEvent();

  @override
  List<Object?> get props => [];
}

/// Load sales invoices live-first for the active date filter.
class LoadInvoices extends SalesInvoiceListEvent {
  const LoadInvoices();
}

/// Pull-to-refresh / app-bar refresh — same live-first path as [LoadInvoices].
class RefreshInvoicesFromZoho extends SalesInvoiceListEvent {
  const RefreshInvoicesFromZoho();
}

/// Updates the list date range and reloads remote invoices for that range.
class SetDateFilter extends SalesInvoiceListEvent {
  final DateTime? startDate;
  final DateTime? endDate;

  const SetDateFilter({this.startDate, this.endDate});

  @override
  List<Object?> get props => [startDate, endDate];
}

/// Batch-converts each open sales order into its own local invoice
/// (one invoice per order) and enqueues Zoho `convert_so` sync items.
class ConvertOrdersBatch extends SalesInvoiceListEvent {
  final List<SalesOrder> orders;

  const ConvertOrdersBatch(this.orders);

  @override
  List<Object?> get props => [orders];
}

/// Clears list error/success snackbar messages.
class ClearInvoiceListMessages extends SalesInvoiceListEvent {
  const ClearInvoiceListMessages();
}
