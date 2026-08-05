import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/ui/features/reports/aggregators/invoice_receipts_summary_aggregator.dart';

void main() {
  final rcpt1 = ReceiptVoucher(
    id: 'rcpt_1',
    paymentNumber: 'PAY-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    allocations: const [
      PaymentAllocation(
        invoiceId: 'inv_1',
        invoiceNumber: 'INV-001',
        amountApplied: 80.0,
      ),
    ],
    amount: 100.0,
    paymentMode: 'Cash',
    referenceNumber: 'REF-001',
    date: DateTime(2026, 8, 1),
  );

  final rcpt2 = ReceiptVoucher(
    id: 'rcpt_2',
    paymentNumber: 'PAY-002',
    customerId: 'cust_2',
    customerName: 'Customer 2',
    allocations: const [
      PaymentAllocation(
        invoiceId: 'inv_2',
        invoiceNumber: 'INV-002',
        amountApplied: 200.0,
      ),
    ],
    amount: 200.0,
    paymentMode: 'Card',
    referenceNumber: 'REF-002',
    date: DateTime(2026, 8, 2),
  );

  final rcpt3 = ReceiptVoucher(
    id: 'rcpt_3',
    paymentNumber: 'PAY-003',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    allocations: const [
      PaymentAllocation(
        invoiceId: 'inv_3',
        invoiceNumber: 'INV-003',
        amountApplied: 50.0,
      ),
    ],
    amount: 150.0,
    paymentMode: 'Cash',
    referenceNumber: 'REF-003',
    date: DateTime(2026, 8, 5),
  );

  group('InvoiceReceiptsSummaryAggregator', () {
    test(
      'aggregates counts, total collected, allocated, and unallocated correctly',
      () {
        final rows = InvoiceReceiptsSummaryAggregator.aggregate(
          receipts: [rcpt1, rcpt2, rcpt3],
        );

        expect(rows.length, equals(2));

        final cashRow = rows.firstWhere((r) => r.mode == 'Cash');
        expect(cashRow.receiptCount, equals(2));
        expect(cashRow.totalCollected, equals(250.0)); // 100 + 150
        expect(cashRow.totalAllocated, equals(130.0)); // 80 + 50
        expect(cashRow.totalUnallocated, equals(120.0)); // 20 + 100

        final cardRow = rows.firstWhere((r) => r.mode == 'Card');
        expect(cardRow.receiptCount, equals(1));
        expect(cardRow.totalCollected, equals(200.0));
        expect(cardRow.totalAllocated, equals(200.0));
        expect(cardRow.totalUnallocated, equals(0.0));
      },
    );

    test('filters by date range correctly', () {
      final rows = InvoiceReceiptsSummaryAggregator.aggregate(
        receipts: [rcpt1, rcpt2, rcpt3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(2));

      final cashRow = rows.firstWhere((r) => r.mode == 'Cash');
      expect(cashRow.receiptCount, equals(1)); // only rcpt1 falls in range
      expect(cashRow.totalCollected, equals(100.0));
    });

    test('sorts by collected descending by default', () {
      final rows = InvoiceReceiptsSummaryAggregator.aggregate(
        receipts: [rcpt1, rcpt2, rcpt3],
        sortField: InvoiceReceiptsSummarySortField.collected,
        sortAscending: false,
      );

      expect(rows.first.mode, equals('Cash')); // 250 > 200
      expect(rows.last.mode, equals('Card'));
    });

    test('sorts by count ascending', () {
      final rows = InvoiceReceiptsSummaryAggregator.aggregate(
        receipts: [rcpt1, rcpt2, rcpt3],
        sortField: InvoiceReceiptsSummarySortField.count,
        sortAscending: true,
      );

      expect(rows.first.mode, equals('Card')); // 1 < 2
      expect(rows.last.mode, equals('Cash'));
    });

    test('sorts by mode ascending', () {
      final rows = InvoiceReceiptsSummaryAggregator.aggregate(
        receipts: [rcpt1, rcpt2, rcpt3],
        sortField: InvoiceReceiptsSummarySortField.mode,
        sortAscending: true,
      );

      expect(rows.first.mode, equals('Card'));
      expect(rows.last.mode, equals('Cash'));
    });

    test('handles empty receipt list', () {
      final rows = InvoiceReceiptsSummaryAggregator.aggregate(receipts: []);
      expect(rows, isEmpty);
    });
  });
}
