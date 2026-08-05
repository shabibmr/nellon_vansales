import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/ui/features/reports/aggregators/customerwise_returns_aggregator.dart';

void main() {
  final item = const Item(
    id: 'item_1',
    name: 'Test Item',
    sku: 'SKU-001',
    rate: 50.0,
    stock: 10.0,
    description: '',
    taxName: '',
    taxPercentage: 0.0,
    uom: 'pcs',
  );

  final lineItem1 = InvoiceLineItem(
    item: item,
    quantity: 2.0,
    rate: 50.0,
    taxPercentage: 0.0,
  );

  final lineItem2 = InvoiceLineItem(
    item: item,
    quantity: 3.0,
    rate: 50.0,
    taxPercentage: 0.0,
  );

  final return1 = SalesReturn(
    id: 'ret_1',
    creditNoteNumber: 'CN-001',
    customerId: 'cust_1',
    customerName: 'Customer A',
    date: DateTime(2026, 8, 1),
    items: [
      SalesReturnLineItem(
        invoiceLineItem: lineItem1,
        returnedQuantity: 2.0, // 100.0
      ),
    ],
    reason: 'Damaged',
  );

  final return2 = SalesReturn(
    id: 'ret_2',
    creditNoteNumber: 'CN-002',
    customerId: 'cust_2',
    customerName: 'Customer B',
    date: DateTime(2026, 8, 2),
    items: [
      SalesReturnLineItem(
        invoiceLineItem: lineItem2,
        returnedQuantity: 3.0, // 150.0
      ),
    ],
    reason: 'Wrong item',
  );

  final return3 = SalesReturn(
    id: 'ret_3',
    creditNoteNumber: 'CN-003',
    customerId: 'cust_1',
    customerName: 'Customer A',
    date: DateTime(2026, 8, 5),
    items: [
      SalesReturnLineItem(
        invoiceLineItem: lineItem1,
        returnedQuantity: 1.0, // 50.0
      ),
    ],
    reason: 'Surplus',
  );

  group('CustomerwiseReturnsAggregator', () {
    test('aggregates return count and total refunded per customer correctly', () {
      final rows = CustomerwiseReturnsAggregator.aggregate(
        returns: [return1, return2, return3],
      );

      expect(rows.length, equals(2));

      final custA = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(custA.customerName, equals('Customer A'));
      expect(custA.returnCount, equals(2));
      expect(custA.totalRefunded, equals(150.0)); // 100 + 50

      final custB = rows.firstWhere((r) => r.customerId == 'cust_2');
      expect(custB.customerName, equals('Customer B'));
      expect(custB.returnCount, equals(1));
      expect(custB.totalRefunded, equals(150.0));
    });

    test('filters by date range correctly', () {
      final rows = CustomerwiseReturnsAggregator.aggregate(
        returns: [return1, return2, return3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(2));

      final custA = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(custA.returnCount, equals(1)); // return3 is excluded
      expect(custA.totalRefunded, equals(100.0));
    });

    test('sorts by amount descending (default)', () {
      final rows = CustomerwiseReturnsAggregator.aggregate(
        returns: [return1, return2, return3],
        sortField: CustomerwiseReturnsSortField.amount,
        sortAscending: false,
      );

      expect(rows.length, equals(2));
      expect(rows[0].totalRefunded, equals(150.0));
    });

    test('sorts by count descending', () {
      final rows = CustomerwiseReturnsAggregator.aggregate(
        returns: [return1, return2, return3],
        sortField: CustomerwiseReturnsSortField.count,
        sortAscending: false,
      );

      expect(rows.first.customerId, equals('cust_1')); // 2 returns > 1 return
      expect(rows.last.customerId, equals('cust_2'));
    });

    test('sorts by name ascending', () {
      final rows = CustomerwiseReturnsAggregator.aggregate(
        returns: [return1, return2, return3],
        sortField: CustomerwiseReturnsSortField.name,
        sortAscending: true,
      );

      expect(rows.first.customerName, equals('Customer A'));
      expect(rows.last.customerName, equals('Customer B'));
    });

    test('handles empty return list', () {
      final rows = CustomerwiseReturnsAggregator.aggregate(returns: []);
      expect(rows, isEmpty);
    });
  });
}
