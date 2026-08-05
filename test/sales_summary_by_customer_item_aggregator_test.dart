import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/ui/features/reports/aggregators/sales_summary_by_customer_item_aggregator.dart';

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

  final inv1 = SalesInvoice(
    id: 'inv_1',
    invoiceNumber: 'INV-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 1),
    dueDate: DateTime(2026, 8, 15),
    items: [
      InvoiceLineItem(item: itemA, quantity: 5.0, rate: 10.0, taxPercentage: 0.0),
      InvoiceLineItem(item: itemB, quantity: 2.0, rate: 5.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final inv2 = SalesInvoice(
    id: 'inv_2',
    invoiceNumber: 'INV-002',
    customerId: 'cust_2',
    customerName: 'Customer 2',
    date: DateTime(2026, 8, 2),
    dueDate: DateTime(2026, 8, 16),
    items: [
      InvoiceLineItem(item: itemA, quantity: 3.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final inv3 = SalesInvoice(
    id: 'inv_3',
    invoiceNumber: 'INV-003',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 8, 5),
    dueDate: DateTime(2026, 8, 19),
    items: [
      InvoiceLineItem(item: itemA, quantity: 10.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  group('SalesSummaryByCustomerItemAggregator', () {
    test('aggregates quantities and amounts by (customer, item) pair correctly', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
      );

      expect(rows.length, equals(3));

      final cust1Apple = rows.firstWhere(
        (r) => r.customerId == 'cust_1' && r.itemId == 'item_1',
      );
      expect(cust1Apple.customerName, equals('Customer 1'));
      expect(cust1Apple.itemName, equals('Apple'));
      expect(cust1Apple.totalQty, equals(15.0)); // 5 + 10
      expect(cust1Apple.totalAmount, equals(150.0)); // 50 + 100

      final cust1Banana = rows.firstWhere(
        (r) => r.customerId == 'cust_1' && r.itemId == 'item_2',
      );
      expect(cust1Banana.totalQty, equals(2.0));
      expect(cust1Banana.totalAmount, equals(10.0));

      final cust2Apple = rows.firstWhere(
        (r) => r.customerId == 'cust_2' && r.itemId == 'item_1',
      );
      expect(cust2Apple.totalQty, equals(3.0));
      expect(cust2Apple.totalAmount, equals(30.0));
    });

    test('filters by date range correctly', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(3));

      final cust1Apple = rows.firstWhere(
        (r) => r.customerId == 'cust_1' && r.itemId == 'item_1',
      );
      expect(cust1Apple.totalQty, equals(5.0));
    });

    test('sorts by amount descending (default)', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerItemSortField.amount,
        sortAscending: false,
      );

      expect(rows.first.totalAmount, equals(150.0));
      expect(rows.last.totalAmount, equals(10.0));
    });

    test('sorts by customer ascending', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerItemSortField.customer,
        sortAscending: true,
      );

      expect(rows.first.customerName, equals('Customer 1'));
    });

    test('sorts by item ascending', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerItemSortField.item,
        sortAscending: true,
      );

      expect(rows.first.itemName, equals('Apple'));
    });

    test('sorts by qty ascending', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerItemSortField.qty,
        sortAscending: true,
      );

      expect(rows.first.totalQty, equals(2.0));
      expect(rows.last.totalQty, equals(15.0));
    });

    test('handles empty invoice list', () {
      final rows = SalesSummaryByCustomerItemAggregator.aggregate(
        invoices: [],
      );
      expect(rows, isEmpty);
    });
  });
}
