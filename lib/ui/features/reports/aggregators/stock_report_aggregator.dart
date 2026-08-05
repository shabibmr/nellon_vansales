import '../../../../domain/models/item.dart';

/// Available sort fields for the stock report.
enum StockReportSortField { name, rate, stock }

/// Pure, framework-agnostic aggregator for filtering and sorting stock report items.
class StockReportAggregator {
  /// Determines whether an [Item] matches the given search [query] against name or SKU.
  static bool matches(Item item, String query) {
    if (query.trim().isEmpty) return true;
    final q = query.trim().toLowerCase();
    return item.name.toLowerCase().contains(q) ||
        item.sku.toLowerCase().contains(q);
  }

  /// Filters items by search query and sorts output rows.
  static List<Item> aggregate({
    required List<Item> items,
    String query = '',
    StockReportSortField sortField = StockReportSortField.name,
    bool sortAscending = true,
  }) {
    final filtered = items.where((item) => matches(item, query)).toList();

    filtered.sort((a, b) {
      final cmp = switch (sortField) {
        StockReportSortField.name => a.name.compareTo(b.name),
        StockReportSortField.rate => a.rate.compareTo(b.rate),
        StockReportSortField.stock => a.stock.compareTo(b.stock),
      };
      return sortAscending ? cmp : -cmp;
    });

    return filtered;
  }
}
