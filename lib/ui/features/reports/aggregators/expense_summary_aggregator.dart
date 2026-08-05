import '../../../../domain/models/expense_entry.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single expense category across the filtered period.
class ExpenseSummaryCategoryRow {
  final String category;
  int entryCount;
  double totalAmount;

  ExpenseSummaryCategoryRow({
    required this.category,
    this.entryCount = 0,
    this.totalAmount = 0.0,
  });
}

/// Available sort fields for the expense summary report.
enum ExpenseSummarySortField { category, count, amount }

/// Pure, framework-agnostic aggregator for computing expense summary report data.
class ExpenseSummaryAggregator {
  /// Aggregates expense entries by category, applies date-range filtering, and sorts output rows.
  static List<ExpenseSummaryCategoryRow> aggregate({
    required List<ExpenseEntry> expenses,
    DateTime? startDate,
    DateTime? endDate,
    ExpenseSummarySortField sortField = ExpenseSummarySortField.amount,
    bool sortAscending = false,
  }) {
    final map = <String, ExpenseSummaryCategoryRow>{};

    final filtered = filterByDateRange(
      expenses,
      (entry) => entry.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final entry in filtered) {
      for (final line in entry.lines) {
        final row = map.putIfAbsent(
          line.category,
          () => ExpenseSummaryCategoryRow(category: line.category),
        );
        row.entryCount++;
        row.totalAmount += line.amount;
      }
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case ExpenseSummarySortField.category:
          cmp = a.category.compareTo(b.category);
          break;
        case ExpenseSummarySortField.count:
          cmp = a.entryCount.compareTo(b.entryCount);
          break;
        case ExpenseSummarySortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
