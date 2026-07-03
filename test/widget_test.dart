import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/item_model.dart';
import 'package:van_sales/data/models/customer_model.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/expense_entry.dart';

void main() {
  group('Van Sales Models Unit Tests', () {
    test('ItemModel serialization and deserialization', () {
      final json = {
        'item_id': 'it_01',
        'name': 'Mineral Water 500ml',
        'rate': 12.0,
        'tax_percentage': 5.0,
        'stock': 150.0,
      };

      final model = ItemModel.fromJson(json);
      expect(model.id, 'it_01');
      expect(model.name, 'Mineral Water 500ml');
      expect(model.rate, 12.0);
      expect(model.taxPercentage, 5.0);
      expect(model.stock, 150.0);

      final serialized = model.toJson();
      expect(serialized['item_id'], 'it_01');
      expect(serialized['rate'], 12.0);
    });

    test('CustomerModel serialization and deserialization', () {
      final json = {
        'contact_id': 'cust_01',
        'contact_name': 'Supermarket Alfa',
        'company_name': 'Alfa Corp',
        'email': 'alfa@example.com',
        'phone': '1234567890',
        'outstanding_balance': 450.00,
        'sequence': 1,
      };

      final model = CustomerModel.fromJson(json);
      expect(model.id, 'cust_01');
      expect(model.outstandingBalance, 450.00);
      expect(model.sequence, 1);

      final serialized = model.toJson();
      expect(serialized['contact_id'], 'cust_01');
      expect(serialized['outstandingBalance'], 450.00);
    });

    test('ReceiptVoucher line allocation math', () {
      final voucher = ReceiptVoucher(
        id: 'pay_01',
        paymentNumber: 'PAY-1001',
        customerId: 'cust_01',
        customerName: 'Supermarket Alfa',
        amount: 250.0,
        paymentMode: 'Cash',
        referenceNumber: 'REF-101',
        date: DateTime.now(),
        allocations: const [
          PaymentAllocation(
            invoiceId: 'inv_01',
            invoiceNumber: 'INV-01',
            amountApplied: 150.0,
          ),
          PaymentAllocation(
            invoiceId: 'inv_02',
            invoiceNumber: 'INV-02',
            amountApplied: 80.0,
          ),
        ],
      );

      expect(voucher.totalAllocated, 230.0);
      expect(voucher.unallocatedAmount, 20.0);
    });

    test('ExpenseEntry multi-line math', () {
      final expense = ExpenseEntry(
        id: 'exp_01',
        date: DateTime.now(),
        lines: const [
          ExpenseLineItem(
            category: 'Fuel',
            amount: 50.0,
            description: 'Van refuel',
          ),
          ExpenseLineItem(
            category: 'Tolls',
            amount: 15.0,
            description: 'Highway toll',
          ),
        ],
      );

      expect(expense.amount, 65.0);
    });
  });
}
