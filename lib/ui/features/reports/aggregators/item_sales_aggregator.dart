import '../../../../domain/models/sales_invoice.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single item across all filtered invoices.
class ItemSalesRow {
  final String itemId;
  final String itemName;
  final String sku;
  double totalQty;
  double totalAmount;
  final Set<String> customerIds;

  ItemSalesRow({
    required this.itemId,
    required this.itemName,
    required this.sku,
    this.totalQty = 0.0,
    this.totalAmount = 0.0,
    Set<String>? customerIds,
  }) : customerIds = customerIds ?? {};

  int get customerCount => customerIds.length;
}

/// Available sort fields for the item sales report.
enum ItemSalesSortField { name, qty, amount, customers }

/// Pure, framework-agnostic aggregator for computing item sales report data.
class ItemSalesAggregator {
  /// Aggregates sales invoices by item, applies date-range filtering, and sorts the output rows.
  static List<ItemSalesRow> aggregate({
    required List<SalesInvoice> invoices,
    DateTime? startDate,
    DateTime? endDate,
    ItemSalesSortField sortField = ItemSalesSortField.amount,
    bool sortAscending = false,
  }) {
    final map = <String, ItemSalesRow>{};

    final filtered = filterByDateRange(
      invoices,
      (inv) => inv.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final inv in filtered) {
      for (final line in inv.items) {
        final row = map.putIfAbsent(
          line.item.id,
          () => ItemSalesRow(
            itemId: line.item.id,
            itemName: line.item.name,
            sku: line.item.sku,
          ),
        );
        row.totalQty += line.quantityInBase;
        row.totalAmount += line.total;
        row.customerIds.add(inv.customerId);
      }
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case ItemSalesSortField.name:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case ItemSalesSortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
          break;
        case ItemSalesSortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
        case ItemSalesSortField.customers:
          cmp = a.customerCount.compareTo(b.customerCount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
