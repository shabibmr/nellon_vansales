import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/ui/features/reports/aggregators/transactions_summary_aggregator.dart';

void main() {
  final inv1 = SalesInvoice(
    id: 'inv_1',
    invoiceNumber: 'INV-001',
    customerId: 'cust_1',
    customerName: 'Customer A',
    date: DateTime(2026, 8, 1),
    dueDate: DateTime(2026, 8, 15),
    items: const [],
    notes: '',
  );

  final inv2 = SalesInvoice(
    id: 'inv_2',
    invoiceNumber: 'INV-002',
    customerId: 'cust_2',
    customerName: 'Customer B',
    date: DateTime(2026, 8, 5),
    dueDate: DateTime(2026, 8, 20),
    items: const [],
    notes: '',
  );

  final rcpt1 = ReceiptVoucher(
    id: 'rcpt_1',
    paymentNumber: 'REC-001',
    customerId: 'cust_1',
    customerName: 'Customer A',
    allocations: const [],
    amount: 150.0,
    paymentMode: 'Cash',
    referenceNumber: '',
    date: DateTime(2026, 8, 2),
  );

  final exp1 = ExpenseEntry(
    id: 'exp_1',
    date: DateTime(2026, 8, 3),
    lines: const [
      ExpenseLineItem(category: 'Fuel', amount: 50.0, description: 'Gas'),
    ],
  );

  final ret1 = SalesReturn(
    id: 'ret_1',
    creditNoteNumber: 'CN-001',
    customerId: 'cust_1',
    customerName: 'Customer A',
    date: DateTime(2026, 8, 4),
    items: const [],
    reason: 'Damaged',
  );

  group('TransactionsSummaryAggregator', () {
    test('aggregates transaction count and amounts per transaction type', () {
      final data = TransactionsReportData(
        invoices: [inv1, inv2],
        receipts: [rcpt1],
        expenses: [exp1],
        returns: [ret1],
      );

      final rows = TransactionsSummaryAggregator.aggregate(data: data);

      expect(rows.length, equals(4));

      final invoiceRow = rows.firstWhere((r) => r.type == 'Invoices');
      expect(invoiceRow.count, equals(2));

      final receiptRow = rows.firstWhere((r) => r.type == 'Receipts');
      expect(receiptRow.count, equals(1));
      expect(receiptRow.totalAmount, equals(150.0));

      final expenseRow = rows.firstWhere((r) => r.type == 'Expenses');
      expect(expenseRow.count, equals(1));
      expect(expenseRow.totalAmount, equals(50.0));

      final returnRow = rows.firstWhere((r) => r.type == 'Sales Returns');
      expect(returnRow.count, equals(1));
    });

    test('filters transactions by date range', () {
      final data = TransactionsReportData(
        invoices: [inv1, inv2],
        receipts: [rcpt1],
        expenses: [exp1],
        returns: [ret1],
      );

      final rows = TransactionsSummaryAggregator.aggregate(
        data: data,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      final invoiceRow = rows.firstWhere((r) => r.type == 'Invoices');
      expect(invoiceRow.count, equals(1)); // inv2 (Aug 5) is excluded

      final returnRow = rows.firstWhere((r) => r.type == 'Sales Returns');
      expect(returnRow.count, equals(0)); // ret1 (Aug 4) is excluded
    });

    test('sorts by amount descending (default)', () {
      final data = TransactionsReportData(
        invoices: [inv1],
        receipts: [rcpt1], // 150.0
        expenses: [exp1], // 50.0
        returns: [ret1],
      );

      final rows = TransactionsSummaryAggregator.aggregate(
        data: data,
        sortField: TransactionsSummarySortField.amount,
        sortAscending: false,
      );

      expect(rows.first.type, equals('Receipts'));
    });

    test('sorts by type ascending', () {
      final data = TransactionsReportData(
        invoices: [inv1],
        receipts: [rcpt1],
        expenses: [exp1],
        returns: [ret1],
      );

      final rows = TransactionsSummaryAggregator.aggregate(
        data: data,
        sortField: TransactionsSummarySortField.type,
        sortAscending: true,
      );

      expect(rows.map((r) => r.type), equals(['Expenses', 'Invoices', 'Receipts', 'Sales Returns']));
    });

    test('handles empty data lists', () {
      const data = TransactionsReportData(
        invoices: [],
        receipts: [],
        expenses: [],
        returns: [],
      );

      final rows = TransactionsSummaryAggregator.aggregate(data: data);
      expect(rows.length, equals(4));
      expect(rows.every((r) => r.count == 0 && r.totalAmount == 0.0), isTrue);
    });
  });
}
