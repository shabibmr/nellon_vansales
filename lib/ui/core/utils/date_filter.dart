/// Filters [items] down to those whose date (from [dateOf]) falls within the
/// inclusive `[startDate, endDate]` range, comparing at day granularity so
/// time-of-day components don't affect inclusion. Either bound may be null
/// to leave that side of the range open.
///
/// Centralizes the date-range filtering logic that was previously
/// duplicated across `SalesInvoiceState`, `SalesOrderState`, `ReceiptState`,
/// `ExpenseState`, and `SalesReturnState`.
List<T> filterByDateRange<T>(
  List<T> items,
  DateTime Function(T item) dateOf, {
  DateTime? startDate,
  DateTime? endDate,
}) {
  return items.where((item) {
    final itemDate = dateOf(item);
    final day = DateTime(itemDate.year, itemDate.month, itemDate.day);
    if (startDate != null) {
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);
      if (day.isBefore(startDay)) return false;
    }
    if (endDate != null) {
      final endDay = DateTime(endDate.year, endDate.month, endDate.day);
      if (day.isAfter(endDay)) return false;
    }
    return true;
  }).toList();
}
