import '../../../../domain/models/sales_invoice.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single (customer, item) pair across the filtered invoices.
class SalesSummaryByCustomerItemRow {
  final String customerId;
  final String customerName;
  final String itemId;
  final String itemName;
  double totalQty;
  double totalAmount;

  SalesSummaryByCustomerItemRow({
    required this.customerId,
    required this.customerName,
    required this.itemId,
    required this.itemName,
    this.totalQty = 0.0,
    this.totalAmount = 0.0,
  });
}

/// Available sort fields for the sales summary by customer and item report.
enum SalesSummaryByCustomerItemSortField { customer, item, qty, amount }

/// Pure, framework-agnostic aggregator for computing sales summary by customer item report data.
class SalesSummaryByCustomerItemAggregator {
  /// Aggregates sales invoices by customer + item pair, applies date-range filtering, and sorts output rows.
  static List<SalesSummaryByCustomerItemRow> aggregate({
    required List<SalesInvoice> invoices,
    DateTime? startDate,
    DateTime? endDate,
    SalesSummaryByCustomerItemSortField sortField =
        SalesSummaryByCustomerItemSortField.amount,
    bool sortAscending = false,
  }) {
    final map = <String, SalesSummaryByCustomerItemRow>{};

    final filtered = filterByDateRange(
      invoices,
      (inv) => inv.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final inv in filtered) {
      for (final line in inv.items) {
        final key = '${inv.customerId}::${line.item.id}';
        final row = map.putIfAbsent(
          key,
          () => SalesSummaryByCustomerItemRow(
            customerId: inv.customerId,
            customerName: inv.customerName,
            itemId: line.item.id,
            itemName: line.item.name,
          ),
        );
        row.totalQty += line.quantityInBase;
        row.totalAmount += line.total;
      }
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case SalesSummaryByCustomerItemSortField.customer:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case SalesSummaryByCustomerItemSortField.item:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case SalesSummaryByCustomerItemSortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
          break;
        case SalesSummaryByCustomerItemSortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
