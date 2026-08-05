import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single transaction type across the filtered period.
class TransactionsSummaryRow {
  final String type;
  int count;
  double totalAmount;

  TransactionsSummaryRow({
    required this.type,
    this.count = 0,
    this.totalAmount = 0.0,
  });
}

/// Available sort fields for the transactions summary report.
enum TransactionsSummarySortField { type, count, amount }

/// Typed payload for the transactions summary report.
class TransactionsReportData {
  final List<SalesInvoice> invoices;
  final List<ReceiptVoucher> receipts;
  final List<ExpenseEntry> expenses;
  final List<SalesReturn> returns;

  const TransactionsReportData({
    required this.invoices,
    required this.receipts,
    required this.expenses,
    required this.returns,
  });
}

/// Pure, framework-agnostic aggregator for computing transactions summary report data.
class TransactionsSummaryAggregator {
  /// Aggregates transactions by type, applies date-range filtering, and sorts output rows.
  static List<TransactionsSummaryRow> aggregate({
    required TransactionsReportData data,
    DateTime? startDate,
    DateTime? endDate,
    TransactionsSummarySortField sortField =
        TransactionsSummarySortField.amount,
    bool sortAscending = false,
  }) {
    final invoiceRow = TransactionsSummaryRow(type: 'Invoices');
    final receiptRow = TransactionsSummaryRow(type: 'Receipts');
    final expenseRow = TransactionsSummaryRow(type: 'Expenses');
    final returnRow = TransactionsSummaryRow(type: 'Sales Returns');

    final filteredInvoices = filterByDateRange(
      data.invoices,
      (i) => i.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final inv in filteredInvoices) {
      invoiceRow.count++;
      invoiceRow.totalAmount += inv.total;
    }

    final filteredReceipts = filterByDateRange(
      data.receipts,
      (r) => r.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final rcpt in filteredReceipts) {
      receiptRow.count++;
      receiptRow.totalAmount += rcpt.amount;
    }

    final filteredExpenses = filterByDateRange(
      data.expenses,
      (e) => e.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final exp in filteredExpenses) {
      expenseRow.count++;
      expenseRow.totalAmount += exp.amount;
    }

    final filteredReturns = filterByDateRange(
      data.returns,
      (r) => r.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final ret in filteredReturns) {
      returnRow.count++;
      returnRow.totalAmount += ret.total;
    }

    final rows = [invoiceRow, receiptRow, expenseRow, returnRow];

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case TransactionsSummarySortField.type:
          cmp = a.type.compareTo(b.type);
          break;
        case TransactionsSummarySortField.count:
          cmp = a.count.compareTo(b.count);
          break;
        case TransactionsSummarySortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
