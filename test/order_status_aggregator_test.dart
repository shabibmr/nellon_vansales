import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/ui/features/reports/aggregators/order_status_aggregator.dart';

void main() {
  final refToday = DateTime(2026, 8, 5);

  final orderInvoiced = SalesOrder(
    id: 'ord_1',
    orderNumber: 'SO-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 1),
    shipmentDate: DateTime(2026, 8, 2),
    items: const [],
    status: SalesOrderStatus.invoiced,
    notes: '',
  );

  final orderDelayed = SalesOrder(
    id: 'ord_2',
    orderNumber: 'SO-002',
    customerId: 'cust_2',
    customerName: 'Customer 2',
    date: DateTime(2026, 8, 1),
    shipmentDate: DateTime(2026, 8, 3), // before Aug 5 -> delayed
    items: const [],
    status: SalesOrderStatus.open,
    notes: '',
  );

  final orderReadyToday = SalesOrder(
    id: 'ord_3',
    orderNumber: 'SO-003',
    customerId: 'cust_3',
    customerName: 'Customer 3',
    date: DateTime(2026, 8, 4),
    shipmentDate: DateTime(2026, 8, 5), // on Aug 5 -> readyOrPending
    items: const [],
    status: SalesOrderStatus.open,
    notes: '',
  );

  final orderReadyFuture = SalesOrder(
    id: 'ord_4',
    orderNumber: 'SO-004',
    customerId: 'cust_4',
    customerName: 'Customer 4',
    date: DateTime(2026, 8, 4),
    shipmentDate: DateTime(2026, 8, 7), // after Aug 5 -> readyOrPending
    items: const [],
    status: SalesOrderStatus.open,
    notes: '',
  );

  final List<SalesOrder> allOrders = [
    orderInvoiced,
    orderDelayed,
    orderReadyToday,
    orderReadyFuture,
  ];

  group('OrderStatusAggregator', () {
    test('filters invoiced orders correctly', () {
      final rows = OrderStatusAggregator.aggregate(
        orders: allOrders,
        filter: OrderStatusFilter.invoiced,
        today: refToday,
      );

      expect(rows.length, equals(1));
      expect(rows.first.id, equals('ord_1'));
    });

    test('filters delayed orders correctly', () {
      final rows = OrderStatusAggregator.aggregate(
        orders: allOrders,
        filter: OrderStatusFilter.delayed,
        today: refToday,
      );

      expect(rows.length, equals(1));
      expect(rows.first.id, equals('ord_2'));
    });

    test('filters ready or pending orders correctly', () {
      final rows = OrderStatusAggregator.aggregate(
        orders: allOrders,
        filter: OrderStatusFilter.readyOrPending,
        today: refToday,
      );

      expect(rows.length, equals(2));
      expect(rows.map((o) => o.id), containsAll(['ord_3', 'ord_4']));
    });

    test('sorts by shipmentDate descending (default)', () {
      final rows = OrderStatusAggregator.aggregate(
        orders: allOrders,
        filter: OrderStatusFilter.readyOrPending,
        sortField: OrderStatusSortField.date,
        sortAscending: false,
        today: refToday,
      );

      expect(rows.first.id, equals('ord_4')); // Aug 7 > Aug 5
      expect(rows.last.id, equals('ord_3'));
    });

    test('sorts by shipmentDate ascending', () {
      final rows = OrderStatusAggregator.aggregate(
        orders: allOrders,
        filter: OrderStatusFilter.readyOrPending,
        sortField: OrderStatusSortField.date,
        sortAscending: true,
        today: refToday,
      );

      expect(rows.first.id, equals('ord_3')); // Aug 5 < Aug 7
      expect(rows.last.id, equals('ord_4'));
    });

    test('handles empty order list', () {
      final rows = OrderStatusAggregator.aggregate(
        orders: [],
        filter: OrderStatusFilter.readyOrPending,
        today: refToday,
      );
      expect(rows, isEmpty);
    });
  });
}
