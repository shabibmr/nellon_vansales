import 'package:equatable/equatable.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/models/receipt_voucher.dart';

class ReceiptAllocationState extends Equatable {
  final Customer? customer;
  final List<OpenInvoice> openInvoices;
  final List<PaymentAllocation> allocations;
  final double paymentAmount;
  final String paymentMode;
  final bool isLoading;
  final bool submitting;
  final String? submitError;
  final bool submitSuccess;
  final bool hasManualOverride;

  const ReceiptAllocationState({
    this.customer,
    this.openInvoices = const [],
    this.allocations = const [],
    this.paymentAmount = 0.0,
    this.paymentMode = 'Cash',
    this.isLoading = false,
    this.submitting = false,
    this.submitError,
    this.submitSuccess = false,
    this.hasManualOverride = false,
  });

  double get totalAllocated => allocations.fold(0.0, (sum, a) => sum + a.amountApplied);

  bool get canSubmit {
    if (paymentAmount <= 0) return false;

    double sumAllocated = 0.0;
    for (final alloc in allocations) {
      if (alloc.amountApplied < 0) return false;
      final inv = openInvoices.firstWhere(
        (i) => i.invoiceId == alloc.invoiceId,
        orElse: () => OpenInvoice(
          invoiceId: '',
          invoiceNumber: '',
          customerId: '',
          date: DateTime(1970),
          dueDate: DateTime(1970),
          total: 0.0,
          balance: 0.0,
          status: '',
        ),
      );
      if (inv.invoiceId.isEmpty || alloc.amountApplied > inv.balance) {
        return false;
      }
      sumAllocated += alloc.amountApplied;
    }

    final roundedSum = double.parse(sumAllocated.toStringAsFixed(2));
    final roundedAmount = double.parse(paymentAmount.toStringAsFixed(2));

    return roundedSum <= roundedAmount;
  }

  ReceiptAllocationState copyWith({
    Customer? customer,
    List<OpenInvoice>? openInvoices,
    List<PaymentAllocation>? allocations,
    double? paymentAmount,
    String? paymentMode,
    bool? isLoading,
    bool? submitting,
    String? submitError,
    bool? submitSuccess,
    bool? hasManualOverride,
    bool clearSubmitError = false,
  }) {
    return ReceiptAllocationState(
      customer: customer ?? this.customer,
      openInvoices: openInvoices ?? this.openInvoices,
      allocations: allocations ?? this.allocations,
      paymentAmount: paymentAmount ?? this.paymentAmount,
      paymentMode: paymentMode ?? this.paymentMode,
      isLoading: isLoading ?? this.isLoading,
      submitting: submitting ?? this.submitting,
      submitError: clearSubmitError ? null : (submitError ?? this.submitError),
      submitSuccess: submitSuccess ?? this.submitSuccess,
      hasManualOverride: hasManualOverride ?? this.hasManualOverride,
    );
  }

  @override
  List<Object?> get props => [
        customer,
        openInvoices,
        allocations,
        paymentAmount,
        paymentMode,
        isLoading,
        submitting,
        submitError,
        submitSuccess,
        hasManualOverride,
      ];
}
