import '../../../../domain/models/stock_transfer.dart';
import '../../../core/utils/date_filter.dart';

/// Available sort fields for the stock transfer history report.
enum StockTransferHistorySortField { date, transferNumber, direction }

/// Pure, framework-agnostic aggregator for filtering and sorting stock
/// transfer history rows.
class StockTransferHistoryAggregator {
  /// Determines whether a [StockTransfer] matches the given search [query]
  /// against its transfer number or notes.
  static bool matches(StockTransfer transfer, String query) {
    if (query.trim().isEmpty) return true;
    final q = query.trim().toLowerCase();
    return transfer.transferNumber.toLowerCase().contains(q) ||
        transfer.notes.toLowerCase().contains(q);
  }

  /// Filters transfers by date range and search query, and sorts output rows.
  static List<StockTransfer> aggregate({
    required List<StockTransfer> transfers,
    DateTime? startDate,
    DateTime? endDate,
    String query = '',
    StockTransferHistorySortField sortField =
        StockTransferHistorySortField.date,
    bool sortAscending = false,
  }) {
    final dateFiltered = filterByDateRange(
      transfers,
      (transfer) => transfer.date,
      startDate: startDate,
      endDate: endDate,
    );
    final filtered = dateFiltered
        .where((transfer) => matches(transfer, query))
        .toList();

    filtered.sort((a, b) {
      final cmp = switch (sortField) {
        StockTransferHistorySortField.date => a.date.compareTo(b.date),
        StockTransferHistorySortField.transferNumber =>
          a.transferNumber.compareTo(b.transferNumber),
        StockTransferHistorySortField.direction =>
          a.direction.name.compareTo(b.direction.name),
      };
      return sortAscending ? cmp : -cmp;
    });

    return filtered;
  }
}
