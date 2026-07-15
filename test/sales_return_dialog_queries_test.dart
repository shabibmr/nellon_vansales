import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/ui/features/dashboard/cubit/sales_return_dialog_queries.dart';

void main() {
  const milk = Item(
    id: 'item_milk',
    name: 'Milk',
    sku: 'MLK-001',
    rate: 10,
    stock: 50,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );

  const bread = Item(
    id: 'item_bread',
    name: 'Bread',
    sku: 'BRD-001',
    rate: 5,
    stock: 20,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );

  const juice = Item(
    id: 'item_juice',
    name: 'Juice',
    sku: 'JCE-001',
    rate: 8,
    stock: 10,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0,
  );

  final olderInvoice = SalesInvoice(
    id: 'inv_old',
    invoiceNumber: 'INV-001',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 1, 1),
    dueDate: DateTime(2026, 1, 15),
    items: const [
      InvoiceLineItem(
        item: milk,
        quantity: 5,
        rate: 10,
        taxPercentage: 0,
      ),
    ],
    notes: '',
  );

  final newerInvoice = SalesInvoice(
    id: 'inv_new',
    invoiceNumber: 'INV-002',
    customerId: 'cust_1',
    customerName: 'Customer 1',
    date: DateTime(2026, 2, 1),
    dueDate: DateTime(2026, 2, 15),
    items: const [
      InvoiceLineItem(
        item: milk,
        quantity: 3,
        rate: 10,
        taxPercentage: 0,
      ),
      InvoiceLineItem(
        item: bread,
        quantity: 2,
        rate: 5,
        taxPercentage: 0,
      ),
    ],
    notes: '',
  );

  final otherCustomerInvoice = SalesInvoice(
    id: 'inv_other',
    invoiceNumber: 'INV-999',
    customerId: 'cust_2',
    customerName: 'Customer 2',
    date: DateTime(2026, 3, 1),
    dueDate: DateTime(2026, 3, 15),
    items: const [
      InvoiceLineItem(
        item: juice,
        quantity: 1,
        rate: 8,
        taxPercentage: 0,
      ),
    ],
    notes: '',
  );

  group('eligibleReturnItems', () {
    test('returns only catalog items purchased by the customer', () {
      final result = eligibleReturnItems(
        allInvoices: [olderInvoice, newerInvoice, otherCustomerInvoice],
        catalog: [milk, bread, juice],
        customerId: 'cust_1',
      );

      expect(result.map((i) => i.id).toList(), ['item_milk', 'item_bread']);
    });

    test('returns empty when customer has no invoices', () {
      final result = eligibleReturnItems(
        allInvoices: [otherCustomerInvoice],
        catalog: [milk, bread],
        customerId: 'cust_1',
      );

      expect(result, isEmpty);
    });
  });

  group('invoicesContainingItem', () {
    test('returns matching invoices sorted newest-first', () {
      final result = invoicesContainingItem(
        allInvoices: [olderInvoice, newerInvoice, otherCustomerInvoice],
        customerId: 'cust_1',
        itemId: 'item_milk',
      );

      expect(result.map((inv) => inv.id).toList(), ['inv_new', 'inv_old']);
    });

    test('excludes invoices for other customers', () {
      final result = invoicesContainingItem(
        allInvoices: [olderInvoice, otherCustomerInvoice],
        customerId: 'cust_1',
        itemId: 'item_juice',
      );

      expect(result, isEmpty);
    });
  });
}