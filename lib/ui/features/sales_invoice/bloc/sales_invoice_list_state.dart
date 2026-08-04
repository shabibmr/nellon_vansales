import 'package:equatable/equatable.dart';

import '../../../../domain/models/sales_invoice.dart';
import '../../../core/utils/date_filter.dart';

/// List-only state for sales invoices (filters, load status, messages).
class SalesInvoiceListState extends Equatable {
  final List<SalesInvoice> invoices;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const SalesInvoiceListState({
    this.invoices = const [],
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

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
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return SalesInvoiceListState(
      invoices: invoices ?? this.invoices,
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
    invoices,
    startDate,
    endDate,
    isLoading,
    errorMessage,
    successMessage,
  ];
}
