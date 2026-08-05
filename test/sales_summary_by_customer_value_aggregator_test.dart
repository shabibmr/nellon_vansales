import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/ui/features/reports/aggregators/sales_summary_by_customer_value_aggregator.dart';

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

  final inv1 = SalesInvoice(
    id: 'inv_1',
    invoiceNumber: 'INV-001',
    customerId: 'cust_1',
    customerName: 'Alpha Store',
    date: DateTime(2026, 8, 1),
    dueDate: DateTime(2026, 8, 15),
    items: [
      InvoiceLineItem(item: itemA, quantity: 5.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final inv2 = SalesInvoice(
    id: 'inv_2',
    invoiceNumber: 'INV-002',
    customerId: 'cust_2',
    customerName: 'Beta Market',
    date: DateTime(2026, 8, 2),
    dueDate: DateTime(2026, 8, 16),
    items: [
      InvoiceLineItem(item: itemA, quantity: 20.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  final inv3 = SalesInvoice(
    id: 'inv_3',
    invoiceNumber: 'INV-003',
    customerId: 'cust_1',
    customerName: 'Alpha Store',
    date: DateTime(2026, 8, 5),
    dueDate: DateTime(2026, 8, 19),
    items: [
      InvoiceLineItem(item: itemA, quantity: 10.0, rate: 10.0, taxPercentage: 0.0),
    ],
    notes: '',
  );

  group('SalesSummaryByCustomerValueAggregator', () {
    test('aggregates invoice counts and total values by customer correctly', () {
      final rows = SalesSummaryByCustomerValueAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
      );

      expect(rows.length, equals(2));

      final alphaRow = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(alphaRow.customerName, equals('Alpha Store'));
      expect(alphaRow.invoiceCount, equals(2));
      expect(alphaRow.totalValue, equals(150.0)); // 50 + 100

      final betaRow = rows.firstWhere((r) => r.customerId == 'cust_2');
      expect(betaRow.customerName, equals('Beta Market'));
      expect(betaRow.invoiceCount, equals(1));
      expect(betaRow.totalValue, equals(200.0)); // 200
    });

    test('filters by date range correctly', () {
      final rows = SalesSummaryByCustomerValueAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(2));

      final alphaRow = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(alphaRow.invoiceCount, equals(1));
      expect(alphaRow.totalValue, equals(50.0));
    });

    test('sorts by value descending (default)', () {
      final rows = SalesSummaryByCustomerValueAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerValueSortField.value,
        sortAscending: false,
      );

      expect(rows.first.customerId, equals('cust_2')); // 200.0 > 150.0
      expect(rows.last.customerId, equals('cust_1'));
    });

    test('sorts by count ascending', () {
      final rows = SalesSummaryByCustomerValueAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerValueSortField.count,
        sortAscending: true,
      );

      expect(rows.first.customerId, equals('cust_2')); // 1 invoice < 2 invoices
      expect(rows.last.customerId, equals('cust_1'));
    });

    test('sorts by name ascending', () {
      final rows = SalesSummaryByCustomerValueAggregator.aggregate(
        invoices: [inv1, inv2, inv3],
        sortField: SalesSummaryByCustomerValueSortField.name,
        sortAscending: true,
      );

      expect(rows.first.customerName, equals('Alpha Store'));
      expect(rows.last.customerName, equals('Beta Market'));
    });

    test('handles empty invoice list', () {
      final rows = SalesSummaryByCustomerValueAggregator.aggregate(
        invoices: [],
      );
      expect(rows, isEmpty);
    });
  });
}
