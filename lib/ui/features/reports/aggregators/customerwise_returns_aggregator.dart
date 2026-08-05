import '../../../../domain/models/sales_return.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single customer across the filtered sales returns.
class CustomerwiseReturnsRow {
  final String customerId;
  final String customerName;
  int returnCount;
  double totalRefunded;

  CustomerwiseReturnsRow({
    required this.customerId,
    required this.customerName,
    this.returnCount = 0,
    this.totalRefunded = 0.0,
  });
}

/// Available sort fields for the customerwise returns summary report.
enum CustomerwiseReturnsSortField { name, count, amount }

/// Pure, framework-agnostic aggregator for computing customerwise sales returns summary report data.
class CustomerwiseReturnsAggregator {
  /// Aggregates sales returns by customer, applies date-range filtering, and sorts output rows.
  static List<CustomerwiseReturnsRow> aggregate({
    required List<SalesReturn> returns,
    DateTime? startDate,
    DateTime? endDate,
    CustomerwiseReturnsSortField sortField =
        CustomerwiseReturnsSortField.amount,
    bool sortAscending = false,
  }) {
    final map = <String, CustomerwiseReturnsRow>{};

    final filtered = filterByDateRange(
      returns,
      (ret) => ret.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final ret in filtered) {
      final row = map.putIfAbsent(
        ret.customerId,
        () => CustomerwiseReturnsRow(
          customerId: ret.customerId,
          customerName: ret.customerName,
        ),
      );
      row.returnCount++;
      row.totalRefunded += ret.total;
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case CustomerwiseReturnsSortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case CustomerwiseReturnsSortField.count:
          cmp = a.returnCount.compareTo(b.returnCount);
          break;
        case CustomerwiseReturnsSortField.amount:
          cmp = a.totalRefunded.compareTo(b.totalRefunded);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
