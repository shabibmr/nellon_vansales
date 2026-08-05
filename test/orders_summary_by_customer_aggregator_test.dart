import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/ui/features/reports/aggregators/orders_summary_by_customer_aggregator.dart';

void main() {
  final itemA = const Item(
    id: 'item_1',
    name: 'Apple',
    sku: 'SKU-APP',
    rate: 10.0,
    stock: 100.0,
    description: 'Fresh Apple',
    taxName: 'VAT',
    taxPercentage: 0.0,
    uom: 'kg',
  );

  final order1 = SalesOrder(
    id: 'ord_1',
    orderNumber: 'SO-001',
    customerId: 'cust_1',
    customerName: 'Alpha Store',
    date: DateTime(2026, 8, 1),
    shipmentDate: DateTime(2026, 8, 2),
    items: [
      OrderLineItem(item: itemA, quantity: 5.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final order2 = SalesOrder(
    id: 'ord_2',
    orderNumber: 'SO-002',
    customerId: 'cust_2',
    customerName: 'Beta Market',
    date: DateTime(2026, 8, 2),
    shipmentDate: DateTime(2026, 8, 3),
    items: [
      OrderLineItem(item: itemA, quantity: 20.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final order3 = SalesOrder(
    id: 'ord_3',
    orderNumber: 'SO-003',
    customerId: 'cust_1',
    customerName: 'Alpha Store',
    date: DateTime(2026, 8, 5),
    shipmentDate: DateTime(2026, 8, 6),
    items: [
      OrderLineItem(item: itemA, quantity: 10.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  group('OrdersSummaryByCustomerAggregator', () {
    test('aggregates order counts and total values by customer correctly', () {
      final rows = OrdersSummaryByCustomerAggregator.aggregate(
        orders: [order1, order2, order3],
      );

      expect(rows.length, equals(2));

      final alphaRow = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(alphaRow.customerName, equals('Alpha Store'));
      expect(alphaRow.orderCount, equals(2));
      expect(alphaRow.totalValue, equals(150.0)); // 50 + 100

      final betaRow = rows.firstWhere((r) => r.customerId == 'cust_2');
      expect(betaRow.customerName, equals('Beta Market'));
      expect(betaRow.orderCount, equals(1));
      expect(betaRow.totalValue, equals(200.0)); // 200
    });

    test('filters by date range correctly', () {
      final rows = OrdersSummaryByCustomerAggregator.aggregate(
        orders: [order1, order2, order3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(2));

      final alphaRow = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(alphaRow.orderCount, equals(1));
      expect(alphaRow.totalValue, equals(50.0));
    });

    test('sorts by value descending (default)', () {
      final rows = OrdersSummaryByCustomerAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: OrdersSummaryByCustomerSortField.value,
        sortAscending: false,
      );

      expect(rows.first.customerId, equals('cust_2')); // 200.0 > 150.0
      expect(rows.last.customerId, equals('cust_1'));
    });

    test('sorts by count ascending', () {
      final rows = OrdersSummaryByCustomerAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: OrdersSummaryByCustomerSortField.count,
        sortAscending: true,
      );

      expect(rows.first.customerId, equals('cust_2')); // 1 order < 2 orders
      expect(rows.last.customerId, equals('cust_1'));
    });

    test('sorts by name ascending', () {
      final rows = OrdersSummaryByCustomerAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: OrdersSummaryByCustomerSortField.name,
        sortAscending: true,
      );

      expect(rows.first.customerName, equals('Alpha Store'));
      expect(rows.last.customerName, equals('Beta Market'));
    });

    test('handles empty order list', () {
      final rows = OrdersSummaryByCustomerAggregator.aggregate(orders: []);
      expect(rows, isEmpty);
    });
  });
}
