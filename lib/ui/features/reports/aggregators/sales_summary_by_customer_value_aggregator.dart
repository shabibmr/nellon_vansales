import '../../../../domain/models/sales_invoice.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single customer across the filtered invoices.
class SalesSummaryByCustomerValueRow {
  final String customerId;
  final String customerName;
  int invoiceCount;
  double totalValue;

  SalesSummaryByCustomerValueRow({
    required this.customerId,
    required this.customerName,
    this.invoiceCount = 0,
    this.totalValue = 0.0,
  });
}

/// Available sort fields for the sales summary by customer (value) report.
enum SalesSummaryByCustomerValueSortField { name, count, value }

/// Pure, framework-agnostic aggregator for computing sales summary by customer (value) report data.
class SalesSummaryByCustomerValueAggregator {
  /// Aggregates sales invoices by customer, applies date-range filtering, and sorts output rows.
  static List<SalesSummaryByCustomerValueRow> aggregate({
    required List<SalesInvoice> invoices,
    DateTime? startDate,
    DateTime? endDate,
    SalesSummaryByCustomerValueSortField sortField =
        SalesSummaryByCustomerValueSortField.value,
    bool sortAscending = false,
  }) {
    final map = <String, SalesSummaryByCustomerValueRow>{};

    final filtered = filterByDateRange(
      invoices,
      (inv) => inv.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final inv in filtered) {
      final row = map.putIfAbsent(
        inv.customerId,
        () => SalesSummaryByCustomerValueRow(
          customerId: inv.customerId,
          customerName: inv.customerName,
        ),
      );
      row.invoiceCount++;
      row.totalValue += inv.total;
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case SalesSummaryByCustomerValueSortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case SalesSummaryByCustomerValueSortField.count:
          cmp = a.invoiceCount.compareTo(b.invoiceCount);
          break;
        case SalesSummaryByCustomerValueSortField.value:
          cmp = a.totalValue.compareTo(b.totalValue);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
