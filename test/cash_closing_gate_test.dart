import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/domain/models/cash_closing.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';

class FakeHiveDatabaseService extends HiveDatabaseService {
  List<SalesInvoice> invoices = [];
  List<ReceiptVoucher> receipts = [];
  List<ExpenseEntry> expenses = [];
  CashClosing? cashClosing;

  @override
  List<SalesInvoice> getLocalInvoices() => invoices;

  @override
  List<ReceiptVoucher> getLocalReceipts() => receipts;

  @override
  List<ExpenseEntry> getLocalExpenses() => expenses;

  @override
  CashClosing? getLocalCashClosing() => cashClosing;
}

void main() {
  const item = Item(
    id: 'item_1',
    name: 'Item One',
    sku: 'SKU1',
    rate: 10.0,
    stock: 10,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0.0,
  );

  group('hasPendingCashClosingForToday', () {
    test('false when there is no activity today', () {
      final db = FakeHiveDatabaseService();
      expect(db.hasPendingCashClosingForToday(), isFalse);
    });

    test('true when there is an invoice today and no closing filed', () {
      final db = FakeHiveDatabaseService()
        ..invoices = [
          SalesInvoice(
            id: 'inv_1',
            invoiceNumber: 'INV-1',
            customerId: 'cust_1',
            customerName: 'Customer',
            date: DateTime.now(),
            dueDate: DateTime.now(),
            items: const [
              InvoiceLineItem(
                item: item,
                quantity: 1,
                rate: 10.0,
                taxPercentage: 0,
              ),
            ],
            notes: '',
          ),
        ];
      expect(db.hasPendingCashClosingForToday(), isTrue);
    });

    test('false when today\'s closing has already been filed', () {
      final db = FakeHiveDatabaseService()
        ..invoices = [
          SalesInvoice(
            id: 'inv_1',
            invoiceNumber: 'INV-1',
            customerId: 'cust_1',
            customerName: 'Customer',
            date: DateTime.now(),
            dueDate: DateTime.now(),
            items: const [
              InvoiceLineItem(
                item: item,
                quantity: 1,
                rate: 10.0,
                taxPercentage: 0,
              ),
            ],
            notes: '',
          ),
        ]
        ..cashClosing = CashClosing(
          id: 'closing_1',
          date: DateTime.now(),
          openingBalance: 0,
          totalSalesInvoices: 10,
          totalReceiptsCollected: 0,
          totalExpenses: 0,
          closingBalance: 0,
          notes: '',
        );
      expect(db.hasPendingCashClosingForToday(), isFalse);
    });

    test('true when the last filed closing is from a previous day', () {
      final db = FakeHiveDatabaseService()
        ..expenses = [
          ExpenseEntry(
            id: 'exp_1',
            date: DateTime.now(),
            lines: const [
              ExpenseLineItem(category: 'Fuel', amount: 5.0, description: ''),
            ],
          ),
        ]
        ..cashClosing = CashClosing(
          id: 'closing_yesterday',
          date: DateTime.now().subtract(const Duration(days: 1)),
          openingBalance: 0,
          totalSalesInvoices: 0,
          totalReceiptsCollected: 0,
          totalExpenses: 5,
          closingBalance: -5,
          notes: '',
        );
      expect(db.hasPendingCashClosingForToday(), isTrue);
    });
  });
}
