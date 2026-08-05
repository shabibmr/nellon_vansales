import '../../../../domain/models/sales_order.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single item across all filtered orders.
class ItemwiseOrdersSummaryRow {
  final String itemId;
  final String itemName;
  final String sku;
  double totalQty;
  double totalAmount;
  final Set<String> customerIds;

  ItemwiseOrdersSummaryRow({
    required this.itemId,
    required this.itemName,
    required this.sku,
    this.totalQty = 0.0,
    this.totalAmount = 0.0,
    Set<String>? customerIds,
  }) : customerIds = customerIds ?? {};

  int get customerCount => customerIds.length;
}

/// Available sort fields for the itemwise orders summary report.
enum ItemwiseOrdersSummarySortField { name, qty, amount, customers }

/// Pure, framework-agnostic aggregator for computing itemwise orders summary report data.
class ItemwiseOrdersSummaryAggregator {
  /// Aggregates sales orders by item, applies date-range filtering, and sorts output rows.
  static List<ItemwiseOrdersSummaryRow> aggregate({
    required List<SalesOrder> orders,
    DateTime? startDate,
    DateTime? endDate,
    ItemwiseOrdersSummarySortField sortField =
        ItemwiseOrdersSummarySortField.amount,
    bool sortAscending = false,
  }) {
    final map = <String, ItemwiseOrdersSummaryRow>{};

    final filtered = filterByDateRange(
      orders,
      (order) => order.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final order in filtered) {
      for (final line in order.items) {
        final row = map.putIfAbsent(
          line.item.id,
          () => ItemwiseOrdersSummaryRow(
            itemId: line.item.id,
            itemName: line.item.name,
            sku: line.item.sku,
          ),
        );
        row.totalQty += line.quantityInBase;
        row.totalAmount += line.total;
        row.customerIds.add(order.customerId);
      }
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case ItemwiseOrdersSummarySortField.name:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case ItemwiseOrdersSummarySortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
          break;
        case ItemwiseOrdersSummarySortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
        case ItemwiseOrdersSummarySortField.customers:
          cmp = a.customerCount.compareTo(b.customerCount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
