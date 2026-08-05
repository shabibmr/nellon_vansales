import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/ui/features/reports/aggregators/itemwise_orders_summary_aggregator.dart';

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

  final itemB = const Item(
    id: 'item_2',
    name: 'Banana',
    sku: 'SKU-BAN',
    rate: 5.0,
    stock: 200.0,
    description: 'Yellow Banana',
    taxName: 'VAT',
    taxPercentage: 0.0,
    uom: 'kg',
  );

  final order1 = SalesOrder(
    id: 'ord_1',
    orderNumber: 'SO-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 1),
    shipmentDate: DateTime(2026, 8, 2),
    items: [
      OrderLineItem(item: itemA, quantity: 5.0, rate: 10.0, taxPercentage: 0.0),
      OrderLineItem(item: itemB, quantity: 2.0, rate: 5.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final order2 = SalesOrder(
    id: 'ord_2',
    orderNumber: 'SO-002',
    customerId: 'cust_2',
    customerName: 'Customer 2',
    date: DateTime(2026, 8, 2),
    shipmentDate: DateTime(2026, 8, 3),
    items: [
      OrderLineItem(item: itemA, quantity: 3.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final order3 = SalesOrder(
    id: 'ord_3',
    orderNumber: 'SO-003',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 5),
    shipmentDate: DateTime(2026, 8, 6),
    items: [
      OrderLineItem(item: itemB, quantity: 10.0, rate: 5.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  group('ItemwiseOrdersSummaryAggregator', () {
    test(
      'aggregates quantities, total amounts, and customer count correctly',
      () {
        final rows = ItemwiseOrdersSummaryAggregator.aggregate(
          orders: [order1, order2, order3],
        );

        expect(rows.length, equals(2));

        final appleRow = rows.firstWhere((r) => r.itemId == 'item_1');
        expect(appleRow.itemName, equals('Apple'));
        expect(appleRow.sku, equals('SKU-APP'));
        expect(appleRow.totalQty, equals(8.0)); // 5 + 3
        expect(appleRow.totalAmount, equals(80.0)); // 50 + 30
        expect(appleRow.customerCount, equals(2)); // cust_1, cust_2

        final bananaRow = rows.firstWhere((r) => r.itemId == 'item_2');
        expect(bananaRow.itemName, equals('Banana'));
        expect(bananaRow.sku, equals('SKU-BAN'));
        expect(bananaRow.totalQty, equals(12.0)); // 2 + 10
        expect(bananaRow.totalAmount, equals(60.0)); // 10 + 50
        expect(bananaRow.customerCount, equals(1)); // cust_1
      },
    );

    test('filters by date range correctly', () {
      final rows = ItemwiseOrdersSummaryAggregator.aggregate(
        orders: [order1, order2, order3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(2));

      final appleRow = rows.firstWhere((r) => r.itemId == 'item_1');
      expect(appleRow.totalQty, equals(8.0));

      final bananaRow = rows.firstWhere((r) => r.itemId == 'item_2');
      expect(bananaRow.totalQty, equals(2.0)); // order1 only
    });

    test('sorts by amount descending (default)', () {
      final rows = ItemwiseOrdersSummaryAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: ItemwiseOrdersSummarySortField.amount,
        sortAscending: false,
      );

      expect(rows.first.itemId, equals('item_1')); // 80.0 > 60.0
      expect(rows.last.itemId, equals('item_2'));
    });

    test('sorts by qty ascending', () {
      final rows = ItemwiseOrdersSummaryAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: ItemwiseOrdersSummarySortField.qty,
        sortAscending: true,
      );

      expect(rows.first.itemId, equals('item_1')); // 8.0 < 12.0
      expect(rows.last.itemId, equals('item_2'));
    });

    test('sorts by name ascending', () {
      final rows = ItemwiseOrdersSummaryAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: ItemwiseOrdersSummarySortField.name,
        sortAscending: true,
      );

      expect(rows.first.itemName, equals('Apple'));
      expect(rows.last.itemName, equals('Banana'));
    });

    test('sorts by customers descending', () {
      final rows = ItemwiseOrdersSummaryAggregator.aggregate(
        orders: [order1, order2, order3],
        sortField: ItemwiseOrdersSummarySortField.customers,
        sortAscending: false,
      );

      expect(rows.first.itemId, equals('item_1')); // 2 customers > 1 customer
    });

    test('handles empty order list', () {
      final rows = ItemwiseOrdersSummaryAggregator.aggregate(orders: []);
      expect(rows, isEmpty);
    });
  });
}
