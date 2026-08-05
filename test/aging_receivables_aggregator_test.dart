import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/open_invoice.dart';
import 'package:van_sales/ui/features/reports/aggregators/aging_receivables_aggregator.dart';

void main() {
  final asOfDate = DateTime(2026, 8, 5);

  final inv0To15 = OpenInvoice(
    invoiceId: 'inv_1',
    invoiceNumber: 'INV-001',
    customerId: 'cust_1',
    date: DateTime(2026, 8, 1),
    dueDate: DateTime(2026, 8, 15),
    total: 1000.0,
    balance: 500.0,
    status: 'partially_paid',
  );

  final inv15To30 = OpenInvoice(
    invoiceId: 'inv_2',
    invoiceNumber: 'INV-002',
    customerId: 'cust_1',
    date: DateTime(2026, 7, 16),
    dueDate: DateTime(2026, 7, 30),
    total: 2000.0,
    balance: 1500.0,
    status: 'unpaid',
  );

  final inv30To60 = OpenInvoice(
    invoiceId: 'inv_3',
    invoiceNumber: 'INV-003',
    customerId: 'cust_2',
    date: DateTime(2026, 7, 1),
    dueDate: DateTime(2026, 7, 15),
    total: 3000.0,
    balance: 3000.0,
    status: 'overdue',
  );

  final inv60Plus = OpenInvoice(
    invoiceId: 'inv_4',
    invoiceNumber: 'INV-004',
    customerId: 'cust_3',
    date: DateTime(2026, 5, 1),
    dueDate: DateTime(2026, 5, 15),
    total: 4000.0,
    balance: 4000.0,
    status: 'overdue',
  );

  final zeroBalanceInv = OpenInvoice(
    invoiceId: 'inv_5',
    invoiceNumber: 'INV-005',
    customerId: 'cust_4',
    date: DateTime(2026, 8, 1),
    dueDate: DateTime(2026, 8, 15),
    total: 500.0,
    balance: 0.0,
    status: 'paid',
  );

  final customerNames = {
    'cust_1': 'Alpha Trading',
    'cust_2': 'Beta Supermarket',
    'cust_3': 'Gamma Enterprise',
  };

  group('AgingReceivablesAggregator', () {
    test('aggregates balances into correct aging buckets per customer', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [inv0To15, inv15To30, inv30To60, inv60Plus, zeroBalanceInv],
        customerNames: customerNames,
        asOfDate: asOfDate,
      );

      expect(rows.length, equals(3));

      final alphaRow = rows.firstWhere((r) => r.customerId == 'cust_1');
      expect(alphaRow.customerName, equals('Alpha Trading'));
      expect(alphaRow.amount(AgingBucket.d0_15), equals(500.0));
      expect(alphaRow.amount(AgingBucket.d15_30), equals(1500.0));
      expect(alphaRow.amount(AgingBucket.d30_60), equals(0.0));
      expect(alphaRow.amount(AgingBucket.d60plus), equals(0.0));
      expect(alphaRow.total, equals(2000.0));

      final betaRow = rows.firstWhere((r) => r.customerId == 'cust_2');
      expect(betaRow.customerName, equals('Beta Supermarket'));
      expect(betaRow.amount(AgingBucket.d30_60), equals(3000.0));
      expect(betaRow.total, equals(3000.0));

      final gammaRow = rows.firstWhere((r) => r.customerId == 'cust_3');
      expect(gammaRow.customerName, equals('Gamma Enterprise'));
      expect(gammaRow.amount(AgingBucket.d60plus), equals(4000.0));
      expect(gammaRow.total, equals(4000.0));
    });

    test('ignores invoices with balance <= 0', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [zeroBalanceInv],
        customerNames: customerNames,
        asOfDate: asOfDate,
      );

      expect(rows, isEmpty);
    });

    test('uses customerId as fallback when customer name is not found', () {
      final invUnknown = OpenInvoice(
        invoiceId: 'inv_6',
        invoiceNumber: 'INV-006',
        customerId: 'cust_unknown',
        date: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 8, 15),
        total: 100.0,
        balance: 100.0,
        status: 'unpaid',
      );

      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [invUnknown],
        customerNames: customerNames,
        asOfDate: asOfDate,
      );

      expect(rows.length, equals(1));
      expect(rows.first.customerName, equals('cust_unknown'));
    });

    test('sorts by total descending (default)', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [inv0To15, inv15To30, inv30To60, inv60Plus],
        customerNames: customerNames,
        asOfDate: asOfDate,
        sortField: AgingSortField.total,
        sortAscending: false,
      );

      expect(
        rows.map((r) => r.customerId).toList(),
        equals(['cust_3', 'cust_2', 'cust_1']),
      );
    });

    test('sorts by total ascending', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [inv0To15, inv15To30, inv30To60, inv60Plus],
        customerNames: customerNames,
        asOfDate: asOfDate,
        sortField: AgingSortField.total,
        sortAscending: true,
      );

      expect(
        rows.map((r) => r.customerId).toList(),
        equals(['cust_1', 'cust_2', 'cust_3']),
      );
    });

    test('sorts by customer name ascending', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [inv0To15, inv15To30, inv30To60, inv60Plus],
        customerNames: customerNames,
        asOfDate: asOfDate,
        sortField: AgingSortField.name,
        sortAscending: true,
      );

      expect(
        rows.map((r) => r.customerName).toList(),
        equals([
          'Alpha Trading',
          'Beta Supermarket',
          'Gamma Enterprise',
        ]),
      );
    });

    test('filters rows by query matching customer name or ID', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [inv0To15, inv15To30, inv30To60, inv60Plus],
        customerNames: customerNames,
        asOfDate: asOfDate,
      );

      final filteredByName = AgingReceivablesAggregator.filter(rows, 'beta');
      expect(filteredByName.length, equals(1));
      expect(filteredByName.first.customerId, equals('cust_2'));

      final filteredById = AgingReceivablesAggregator.filter(rows, 'cust_3');
      expect(filteredById.length, equals(1));
      expect(filteredById.first.customerName, equals('Gamma Enterprise'));

      final filteredEmpty = AgingReceivablesAggregator.filter(rows, '');
      expect(filteredEmpty.length, equals(3));
    });

    test('returns empty list when input invoices are empty', () {
      final rows = AgingReceivablesAggregator.aggregate(
        openInvoices: [],
        customerNames: customerNames,
        asOfDate: asOfDate,
      );

      expect(rows, isEmpty);
    });

    test('AgingBucketLabel returns correct display string', () {
      expect(AgingBucket.d0_15.label, equals('0-15'));
      expect(AgingBucket.d15_30.label, equals('15-30'));
      expect(AgingBucket.d30_60.label, equals('30-60'));
      expect(AgingBucket.d60plus.label, equals('>60'));
    });
  });
}
