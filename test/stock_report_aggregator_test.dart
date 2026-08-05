import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/ui/features/reports/aggregators/stock_report_aggregator.dart';

void main() {
  const item1 = Item(
    id: 'item_1',
    name: 'Apple Juice',
    sku: 'SKU-APP-01',
    rate: 15.50,
    stock: 100.0,
    description: 'Fresh apple juice',
    taxName: 'VAT',
    taxPercentage: 5.0,
  );

  const item2 = Item(
    id: 'item_2',
    name: 'Banana Milkshake',
    sku: 'SKU-BAN-02',
    rate: 25.00,
    stock: 15.0,
    description: 'Banana milkshake bottle',
    taxName: 'VAT',
    taxPercentage: 5.0,
  );

  const item3 = Item(
    id: 'item_3',
    name: 'Cherry Soda',
    sku: 'SKU-CHE-03',
    rate: 10.00,
    stock: 50.0,
    description: 'Carbonated cherry drink',
    taxName: 'VAT',
    taxPercentage: 5.0,
  );

  group('StockReportAggregator', () {
    test('matches items by name or SKU case-insensitively', () {
      expect(StockReportAggregator.matches(item1, 'apple'), isTrue);
      expect(StockReportAggregator.matches(item1, 'APP-01'), isTrue);
      expect(StockReportAggregator.matches(item1, 'orange'), isFalse);
      expect(StockReportAggregator.matches(item1, ''), isTrue);
    });

    test('filters items by search query', () {
      final rows = StockReportAggregator.aggregate(
        items: [item1, item2, item3],
        query: 'banana',
      );

      expect(rows.length, equals(1));
      expect(rows.first.name, equals('Banana Milkshake'));
    });

    test('sorts by name ascending and descending', () {
      final asc = StockReportAggregator.aggregate(
        items: [item2, item1, item3],
        sortField: StockReportSortField.name,
        sortAscending: true,
      );
      expect(asc.map((i) => i.name), equals(['Apple Juice', 'Banana Milkshake', 'Cherry Soda']));

      final desc = StockReportAggregator.aggregate(
        items: [item2, item1, item3],
        sortField: StockReportSortField.name,
        sortAscending: false,
      );
      expect(desc.map((i) => i.name), equals(['Cherry Soda', 'Banana Milkshake', 'Apple Juice']));
    });

    test('sorts by rate ascending and descending', () {
      final asc = StockReportAggregator.aggregate(
        items: [item1, item2, item3],
        sortField: StockReportSortField.rate,
        sortAscending: true,
      );
      expect(asc.map((i) => i.name), equals(['Cherry Soda', 'Apple Juice', 'Banana Milkshake']));

      final desc = StockReportAggregator.aggregate(
        items: [item1, item2, item3],
        sortField: StockReportSortField.rate,
        sortAscending: false,
      );
      expect(desc.map((i) => i.name), equals(['Banana Milkshake', 'Apple Juice', 'Cherry Soda']));
    });

    test('sorts by stock ascending and descending', () {
      final asc = StockReportAggregator.aggregate(
        items: [item1, item2, item3],
        sortField: StockReportSortField.stock,
        sortAscending: true,
      );
      expect(asc.map((i) => i.name), equals(['Banana Milkshake', 'Cherry Soda', 'Apple Juice']));

      final desc = StockReportAggregator.aggregate(
        items: [item1, item2, item3],
        sortField: StockReportSortField.stock,
        sortAscending: false,
      );
      expect(desc.map((i) => i.name), equals(['Apple Juice', 'Cherry Soda', 'Banana Milkshake']));
    });

    test('handles empty item list', () {
      final rows = StockReportAggregator.aggregate(items: []);
      expect(rows, isEmpty);
    });
  });
}
