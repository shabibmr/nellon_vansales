import '../../../../domain/models/sales_order.dart';
import '../../../core/utils/date_filter.dart';

/// Aggregated row for a single customer across the filtered orders.
class OrdersSummaryByCustomerRow {
  final String customerId;
  final String customerName;
  int orderCount;
  double totalValue;

  OrdersSummaryByCustomerRow({
    required this.customerId,
    required this.customerName,
    this.orderCount = 0,
    this.totalValue = 0.0,
  });
}

/// Available sort fields for the orders summary by customer report.
enum OrdersSummaryByCustomerSortField { name, count, value }

/// Pure, framework-agnostic aggregator for computing orders summary by customer report data.
class OrdersSummaryByCustomerAggregator {
  /// Aggregates sales orders by customer, applies date-range filtering, and sorts output rows.
  static List<OrdersSummaryByCustomerRow> aggregate({
    required List<SalesOrder> orders,
    DateTime? startDate,
    DateTime? endDate,
    OrdersSummaryByCustomerSortField sortField =
        OrdersSummaryByCustomerSortField.value,
    bool sortAscending = false,
  }) {
    final map = <String, OrdersSummaryByCustomerRow>{};

    final filtered = filterByDateRange(
      orders,
      (order) => order.date,
      startDate: startDate,
      endDate: endDate,
    );
    for (final order in filtered) {
      final row = map.putIfAbsent(
        order.customerId,
        () => OrdersSummaryByCustomerRow(
          customerId: order.customerId,
          customerName: order.customerName,
        ),
      );
      row.orderCount++;
      row.totalValue += order.total;
    }

    final rows = map.values.toList();

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case OrdersSummaryByCustomerSortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case OrdersSummaryByCustomerSortField.count:
          cmp = a.orderCount.compareTo(b.orderCount);
          break;
        case OrdersSummaryByCustomerSortField.value:
          cmp = a.totalValue.compareTo(b.totalValue);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return rows;
  }
}
