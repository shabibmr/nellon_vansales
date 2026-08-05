import '../../../../domain/models/sales_return.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single item across all filtered sales returns.
class ItemwiseReturnsSummaryRow {
  final String itemId;
  final String itemName;
  final String sku;
  double totalQty;
  double totalRefunded;

  ItemwiseReturnsSummaryRow({
    required this.itemId,
    required this.itemName,
    required this.sku,
    this.totalQty = 0.0,
    this.totalRefunded = 0.0,
  });
}

/// Available sort fields for the itemwise sales-returns summary report.
enum ItemwiseReturnsSummarySortField { name, qty, amount }

/// Pure, framework-agnostic aggregator for computing itemwise sales-returns summary report data.
class ItemwiseReturnsSummaryAggregator {
  /// Aggregates sales returns by item, applies date-range filtering, and sorts output rows.
  static List<ItemwiseReturnsSummaryRow> aggregate({
    required List<SalesReturn> returns,
    DateTime? startDate,
    DateTime? endDate,
    ItemwiseReturnsSummarySortField sortField =
        ItemwiseReturnsSummarySortField.amount,
    bool sortAscending = false,
  }) {
    final map = <String, ItemwiseReturnsSummaryRow>{};

    final filtered = filterByDateRange(
      returns,
      (ret) => ret.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final ret in filtered) {
      for (final line in ret.items) {
        final item = line.invoiceLineItem.item;
        final row = map.putIfAbsent(
          item.id,
          () => ItemwiseReturnsSummaryRow(
            itemId: item.id,
            itemName: item.name,
            sku: item.sku,
          ),
        );
        row.totalQty += line.returnedQuantityInBase;
        row.totalRefunded += line.total;
      }
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case ItemwiseReturnsSummarySortField.name:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case ItemwiseReturnsSummarySortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
          break;
        case ItemwiseReturnsSummarySortField.amount:
          cmp = a.totalRefunded.compareTo(b.totalRefunded);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
