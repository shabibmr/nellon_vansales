import '../models/open_invoice.dart';
import '../models/receipt_voucher.dart';

/// Rules for spreading a customer payment across open invoices.
///
/// Shared by the dashboard quick-receipt flow and the receipt editor so the
/// oldest-first default, the per-invoice cap and the over-payment tolerance
/// cannot drift apart.
class AllocationRules {
  AllocationRules._();

  /// Amounts within half a cent of a limit count as within it.
  static const double tolerance = 0.005;

  static double round2(double v) => double.parse(v.toStringAsFixed(2));

  static double total(Iterable<PaymentAllocation> allocations) =>
      allocations.fold(0.0, (s, a) => s + a.amountApplied);

  /// True when [amount] exceeds [limit] by more than the rounding tolerance.
  static bool exceeds(double amount, double limit) => amount > limit + tolerance;

  /// How much of [remaining] payment [invoice] can take.
  static double fillFor(OpenInvoice invoice, double remaining) {
    if (remaining <= 0) return 0;
    return remaining < invoice.balance ? remaining : invoice.balance;
  }

  /// Oldest-first allocation of [amount] across [openInvoices], capping each
  /// invoice at its balance. Anything left over stays unallocated.
  static List<PaymentAllocation> autoAllocate(
    List<OpenInvoice> openInvoices,
    double amount,
  ) {
    if (amount <= 0) return const [];
    final sorted = List<OpenInvoice>.of(openInvoices)
      ..sort((a, b) => a.date.compareTo(b.date));

    final allocations = <PaymentAllocation>[];
    var remaining = amount;
    for (final invoice in sorted) {
      if (remaining <= 0) break;
      if (invoice.balance <= 0) continue;
      final allocated = fillFor(invoice, remaining);
      allocations.add(
        PaymentAllocation(
          invoiceId: invoice.invoiceId,
          invoiceNumber: invoice.invoiceNumber,
          amountApplied: round2(allocated),
        ),
      );
      remaining = round2(remaining - allocated);
    }
    return allocations;
  }
}
