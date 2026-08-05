import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single payment mode across the filtered period.
class InvoiceReceiptsSummaryRow {
  final String mode;
  int receiptCount;
  double totalCollected;
  double totalAllocated;
  double totalUnallocated;

  InvoiceReceiptsSummaryRow({
    required this.mode,
    this.receiptCount = 0,
    this.totalCollected = 0.0,
    this.totalAllocated = 0.0,
    this.totalUnallocated = 0.0,
  });
}

/// Available sort fields for the invoice receipts summary report.
enum InvoiceReceiptsSummarySortField { mode, count, collected }

/// Pure, framework-agnostic aggregator for computing invoice receipts summary report data.
class InvoiceReceiptsSummaryAggregator {
  /// Aggregates receipt vouchers by payment mode, applies date-range filtering, and sorts output rows.
  static List<InvoiceReceiptsSummaryRow> aggregate({
    required List<ReceiptVoucher> receipts,
    DateTime? startDate,
    DateTime? endDate,
    InvoiceReceiptsSummarySortField sortField =
        InvoiceReceiptsSummarySortField.collected,
    bool sortAscending = false,
  }) {
    final map = <String, InvoiceReceiptsSummaryRow>{};

    final filtered = filterByDateRange(
      receipts,
      (rcpt) => rcpt.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final rcpt in filtered) {
      final row = map.putIfAbsent(
        rcpt.paymentMode,
        () => InvoiceReceiptsSummaryRow(mode: rcpt.paymentMode),
      );
      row.receiptCount++;
      row.totalCollected += rcpt.amount;
      row.totalAllocated += rcpt.totalAllocated;
      row.totalUnallocated += rcpt.unallocatedAmount;
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case InvoiceReceiptsSummarySortField.mode:
          cmp = a.mode.compareTo(b.mode);
          break;
        case InvoiceReceiptsSummarySortField.count:
          cmp = a.receiptCount.compareTo(b.receiptCount);
          break;
        case InvoiceReceiptsSummarySortField.collected:
          cmp = a.totalCollected.compareTo(b.totalCollected);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
