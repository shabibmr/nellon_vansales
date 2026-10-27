import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/utils/allocation_rules.dart';

class ReceiptAllocationsSheetState extends Equatable {
  /// Open invoices, oldest first.
  final List<OpenInvoice> invoices;

  /// Amount typed per invoice id; absent means not allocated.
  final Map<String, double> amounts;
  final double paymentAmount;

  const ReceiptAllocationsSheetState({
    required this.invoices,
    required this.amounts,
    required this.paymentAmount,
  });

  double amountFor(String invoiceId) => amounts[invoiceId] ?? 0.0;

  double get totalAllocated => amounts.values.fold(0.0, (s, v) => s + v);

  bool isInvoiceOverflow(OpenInvoice inv) =>
      AllocationRules.exceeds(amountFor(inv.invoiceId), inv.balance);

  bool get hasInvoiceOverflow => invoices.any(isInvoiceOverflow);

  bool get isOverPayment =>
      AllocationRules.exceeds(totalAllocated, paymentAmount);

  bool get canApply => !hasInvoiceOverflow && !isOverPayment;

  List<PaymentAllocation> toAllocations() => [
    for (final inv in invoices)
      if (amountFor(inv.invoiceId) > 0)
        PaymentAllocation(
          invoiceId: inv.invoiceId,
          invoiceNumber: inv.invoiceNumber,
          amountApplied: AllocationRules.round2(amountFor(inv.invoiceId)),
        ),
  ];

  @override
  List<Object?> get props => [invoices, amounts, paymentAmount];
}

/// Editing state for the receipt "allocate to invoices" sheet.
class ReceiptAllocationsSheetCubit extends Cubit<ReceiptAllocationsSheetState> {
  ReceiptAllocationsSheetCubit({
    required List<OpenInvoice> openInvoices,
    required List<PaymentAllocation> allocations,
    required double paymentAmount,
  }) : super(
         ReceiptAllocationsSheetState(
           invoices: List.of(openInvoices)
             ..sort((a, b) => a.date.compareTo(b.date)),
           // Allocations to invoices that are no longer open are dropped so
           // the header total only counts rows the user can see and edit.
           amounts: {
             for (final a in allocations)
               if (a.amountApplied > 0 &&
                   openInvoices.any((i) => i.invoiceId == a.invoiceId))
                 a.invoiceId: a.amountApplied,
           },
           paymentAmount: paymentAmount,
         ),
       );

  /// Sets the amount for [invoiceId] from raw text; blank/invalid clears it.
  void setAmount(String invoiceId, String rawValue) {
    final parsed = double.tryParse(rawValue) ?? 0.0;
    _put(invoiceId, parsed.isFinite ? parsed : 0.0);
  }

  /// Puts as much of the unallocated payment as fits into [invoiceId].
  void fillRemaining(String invoiceId) {
    final inv = state.invoices.firstWhere((i) => i.invoiceId == invoiceId);
    final others = state.totalAllocated - state.amountFor(invoiceId);
    _put(invoiceId, AllocationRules.fillFor(inv, state.paymentAmount - others));
  }

  void _put(String invoiceId, double value) {
    final amounts = Map<String, double>.of(state.amounts);
    if (value > 0) {
      amounts[invoiceId] = value;
    } else {
      amounts.remove(invoiceId);
    }
    emit(
      ReceiptAllocationsSheetState(
        invoices: state.invoices,
        amounts: amounts,
        paymentAmount: state.paymentAmount,
      ),
    );
  }
}
