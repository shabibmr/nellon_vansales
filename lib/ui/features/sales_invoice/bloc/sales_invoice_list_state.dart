import 'package:equatable/equatable.dart';

import '../../../../domain/models/sales_invoice.dart';
import '../../../core/utils/date_filter.dart';

/// Load lifecycle for the sales invoice list.
enum SalesInvoiceListStatus { initial, loading, success, failure }

/// List-only state for sales invoices (filters, load status, messages).
class SalesInvoiceListState extends Equatable {
  final List<SalesInvoice> invoices;
  final DateTime? startDate;
  final DateTime? endDate;
  final SalesInvoiceListStatus status;
  final String? errorMessage;
  final String? successMessage;

  const SalesInvoiceListState({
    this.invoices = const [],
    this.startDate,
    this.endDate,
    this.status = SalesInvoiceListStatus.initial,
    this.errorMessage,
    this.successMessage,
  });

  /// True while a remote list fetch is in flight.
  bool get isLoading => status == SalesInvoiceListStatus.loading;

  /// Invoices filtered by the active date range.
  List<SalesInvoice> get filteredInvoices => filterByDateRange(
    invoices,
    (inv) => inv.date,
    startDate: startDate,
    endDate: endDate,
  );

  SalesInvoiceListState copyWith({
    List<SalesInvoice>? invoices,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    SalesInvoiceListStatus? status,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    final nextStatus = status ??
        (isLoading == null
            ? this.status
            : (isLoading
                ? SalesInvoiceListStatus.loading
                : SalesInvoiceListStatus.success));

    return SalesInvoiceListState(
      invoices: invoices ?? this.invoices,
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
    invoices,
    startDate,
    endDate,
    status,
    errorMessage,
    successMessage,
  ];
}
