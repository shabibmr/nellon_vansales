import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/ui/features/reports/aggregators/itemwise_returns_summary_aggregator.dart';

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

  final invLineA = InvoiceLineItem(
    item: itemA,
    quantity: 10.0,
    rate: 10.0,
    taxPercentage: 0.0,
  );

  final invLineB = InvoiceLineItem(
    item: itemB,
    quantity: 20.0,
    rate: 5.0,
    taxPercentage: 0.0,
  );

  final return1 = SalesReturn(
    id: 'ret_1',
    creditNoteNumber: 'CN-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 1),
    items: [
      SalesReturnLineItem(
        invoiceLineItem: invLineA,
        returnedQuantity: 2.0, // total = 20.0
      ),
      SalesReturnLineItem(
        invoiceLineItem: invLineB,
        returnedQuantity: 4.0, // total = 20.0
      ),
    ],
    reason: 'Damaged',
  );

  final return2 = SalesReturn(
    id: 'ret_2',
    creditNoteNumber: 'CN-002',
    customerId: 'cust_2',
    customerName: 'Customer 2',
    date: DateTime(2026, 8, 3),
    items: [
      SalesReturnLineItem(
        invoiceLineItem: invLineA,
        returnedQuantity: 3.0, // total = 30.0
      ),
    ],
    reason: 'Surplus',
  );

  final return3 = SalesReturn(
    id: 'ret_3',
    creditNoteNumber: 'CN-003',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 6),
    items: [
      SalesReturnLineItem(
        invoiceLineItem: invLineB,
        returnedQuantity: 10.0, // total = 50.0
      ),
    ],
    reason: 'Incorrect item',
  );

  group('ItemwiseReturnsSummaryAggregator', () {
    test('aggregates returned quantities and refunded amounts correctly', () {
      final rows = ItemwiseReturnsSummaryAggregator.aggregate(
        returns: [return1, return2, return3],
      );

      expect(rows.length, equals(2));

      final appleRow = rows.firstWhere((r) => r.itemId == 'item_1');
      expect(appleRow.itemName, equals('Apple'));
      expect(appleRow.sku, equals('SKU-APP'));
      expect(appleRow.totalQty, equals(5.0)); // 2 + 3
      expect(appleRow.totalRefunded, equals(50.0)); // 20 + 30

      final bananaRow = rows.firstWhere((r) => r.itemId == 'item_2');
      expect(bananaRow.itemName, equals('Banana'));
      expect(bananaRow.sku, equals('SKU-BAN'));
      expect(bananaRow.totalQty, equals(14.0)); // 4 + 10
      expect(bananaRow.totalRefunded, equals(70.0)); // 20 + 50
    });

    test('filters by date range correctly', () {
      final rows = ItemwiseReturnsSummaryAggregator.aggregate(
        returns: [return1, return2, return3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 4),
      );

      expect(rows.length, equals(2));

      final appleRow = rows.firstWhere((r) => r.itemId == 'item_1');
      expect(appleRow.totalQty, equals(5.0)); // return1 + return2

      final bananaRow = rows.firstWhere((r) => r.itemId == 'item_2');
      expect(bananaRow.totalQty, equals(4.0)); // return1 only
    });

    test('sorts by amount descending (default)', () {
      final rows = ItemwiseReturnsSummaryAggregator.aggregate(
        returns: [return1, return2, return3],
        sortField: ItemwiseReturnsSummarySortField.amount,
        sortAscending: false,
      );

      expect(rows.first.itemId, equals('item_2')); // 70.0 > 50.0
      expect(rows.last.itemId, equals('item_1'));
    });

    test('sorts by qty ascending', () {
      final rows = ItemwiseReturnsSummaryAggregator.aggregate(
        returns: [return1, return2, return3],
        sortField: ItemwiseReturnsSummarySortField.qty,
        sortAscending: true,
      );

      expect(rows.first.itemId, equals('item_1')); // 5.0 < 14.0
      expect(rows.last.itemId, equals('item_2'));
    });

    test('sorts by name ascending', () {
      final rows = ItemwiseReturnsSummaryAggregator.aggregate(
        returns: [return1, return2, return3],
        sortField: ItemwiseReturnsSummarySortField.name,
        sortAscending: true,
      );

      expect(rows.first.itemName, equals('Apple'));
      expect(rows.last.itemName, equals('Banana'));
    });

    test('handles empty sales returns list', () {
      final rows = ItemwiseReturnsSummaryAggregator.aggregate(returns: []);
      expect(rows, isEmpty);
    });
  });
}
