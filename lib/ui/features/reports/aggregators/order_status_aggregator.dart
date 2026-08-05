import '../../../../domain/models/sales_order.dart';

/// Available sort fields for the order status report page.
enum OrderStatusSortField { date, total }

/// Which lifecycle bucket of sales orders an order status report shows.
///
/// [readyOrPending] backs both the "Orders Ready" and "Pending Orders" tiles:
/// `SalesOrder` has no fulfillment-progress field beyond `status`/
/// `shipmentDate`, so there is nothing in the data model today that
/// distinguishes "ready to ship" from "not yet prepared" — both tiles
/// intentionally show the same open-and-not-delayed bucket.
enum OrderStatusFilter { readyOrPending, invoiced, delayed }

/// Pure, framework-agnostic aggregator for filtering and sorting order status report data.
class OrderStatusAggregator {
  /// Checks whether a [SalesOrder] matches the specified [OrderStatusFilter].
  static bool matches(
    SalesOrder order,
    OrderStatusFilter filter, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final shipDay = DateTime(
      order.shipmentDate.year,
      order.shipmentDate.month,
      order.shipmentDate.day,
    );
    final todayDay = DateTime(now.year, now.month, now.day);

    switch (filter) {
      case OrderStatusFilter.invoiced:
        return order.isConverted;
      case OrderStatusFilter.delayed:
        return !order.isConverted && shipDay.isBefore(todayDay);
      case OrderStatusFilter.readyOrPending:
        return !order.isConverted && !shipDay.isBefore(todayDay);
    }
  }

  /// Filters sales orders by lifecycle status bucket and sorts them.
  static List<SalesOrder> aggregate({
    required List<SalesOrder> orders,
    required OrderStatusFilter filter,
    OrderStatusSortField sortField = OrderStatusSortField.date,
    bool sortAscending = false,
    DateTime? today,
  }) {
    final filtered =
        orders.where((o) => matches(o, filter, today: today)).toList();

    filtered.sort((a, b) {
      final cmp = switch (sortField) {
        OrderStatusSortField.date => a.shipmentDate.compareTo(b.shipmentDate),
        OrderStatusSortField.total => a.total.compareTo(b.total),
      };
      return sortAscending ? cmp : -cmp;
    });

    return filtered;
  }
}
