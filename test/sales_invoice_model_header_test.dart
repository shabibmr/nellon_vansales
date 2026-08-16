import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sales_invoice_model.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';

void main() {
  group('SalesInvoiceModel header vs detail', () {
    test('header JSON maps status and listedTotal without line items', () {
      final inv = SalesInvoiceModel.fromJson({
        'invoice_id': 'inv_1',
        'invoice_number': 'INV-001',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'due_date': '2026-03-08',
        'status': 'partially_paid',
        'total': 1500.5,
      });

      expect(inv.id, 'inv_1');
      expect(inv.status, 'partially_paid');
      expect(inv.listedTotal, 1500.5);
      expect(inv.items, isEmpty);
      expect(inv.total, 1501.0); // listedTotal rounded
    });

    test('line items win over listedTotal for total', () {
      const item = Item(
        id: 'i1',
        name: 'Widget',
        sku: 'W1',
        rate: 10,
        taxPercentage: 0,
        stock: 100,
        description: '',
        taxName: '',
        uom: 'pcs',
      );
      final inv = SalesInvoice(
        id: 'inv_2',
        invoiceNumber: 'INV-002',
        customerId: 'c1',
        customerName: 'Acme',
        date: DateTime(2026, 3, 1),
        dueDate: DateTime(2026, 3, 8),
        items: const [
          InvoiceLineItem(
            item: item,
            quantity: 2,
            rate: 10,
            taxPercentage: 0,
          ),
        ],
        notes: '',
        listedTotal: 9999,
      );

      expect(inv.total, 20.0);
    });

    test('toJson/fromJson round-trips status and listedTotal', () {
      final original = SalesInvoiceModel.fromJson({
        'invoice_id': 'inv_3',
        'invoice_number': 'INV-003',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'due_date': '2026-03-08',
        'status': 'unpaid',
        'total': 200,
      });
      final again = SalesInvoiceModel.fromJson(original.toJson());
      expect(again.status, 'unpaid');
      expect(again.listedTotal, 200);
      expect(again.total, 200);
    });

    test('toJson/fromJson round-trips zohoInvoiceId without using it as id', () {
      final original = SalesInvoiceModel.fromJson({
        'id': 'temp_inv_9',
        'invoice_id': 'temp_inv_9',
        'invoice_number': 'INV-009',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'due_date': '2026-03-08',
        'zoho_invoice_id': 'zoho_inv_9',
        'isPendingSync': false,
      });
      expect(original.id, 'temp_inv_9');
      expect(original.zohoInvoiceId, 'zoho_inv_9');

      final again = SalesInvoiceModel.fromJson(original.toJson());
      expect(again.id, 'temp_inv_9');
      expect(again.zohoInvoiceId, 'zoho_inv_9');
    });
  });

  group('InvoiceLineItemModel numeric field parsing', () {
    test('parses quantity/rate/tax_percentage/discount given as strings', () {
      final inv = SalesInvoiceModel.fromJson({
        'invoice_id': 'inv_4',
        'invoice_number': 'INV-004',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'due_date': '2026-03-08',
        'line_items': [
          {
            'item_id': 'i1',
            'name': 'Widget',
            'sku': 'W1',
            'quantity': '24',
            'rate': '60.00',
            'tax_percentage': '5.0',
            'discount': '1.5',
          },
        ],
      });

      expect(inv.items, hasLength(1));
      final line = inv.items.first;
      expect(line.quantity, 24.0);
      expect(line.rate, 60.0);
      expect(line.taxPercentage, 5.0);
      expect(line.discount, 1.5);
    });

    test('parses quantity/rate/tax_percentage/discount given as numbers', () {
      final inv = SalesInvoiceModel.fromJson({
        'invoice_id': 'inv_5',
        'invoice_number': 'INV-005',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'due_date': '2026-03-08',
        'line_items': [
          {
            'item_id': 'i1',
            'name': 'Widget',
            'sku': 'W1',
            'quantity': 24,
            'rate': 60.00,
            'tax_percentage': 5.0,
            'discount': 1.5,
          },
        ],
      });

      final line = inv.items.first;
      expect(line.quantity, 24.0);
      expect(line.rate, 60.0);
      expect(line.taxPercentage, 5.0);
      expect(line.discount, 1.5);
    });

    test('missing numeric fields fall back to defaults without throwing', () {
      final inv = SalesInvoiceModel.fromJson({
        'invoice_id': 'inv_6',
        'invoice_number': 'INV-006',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'due_date': '2026-03-08',
        'line_items': [
          {'item_id': 'i1', 'name': 'Widget', 'sku': 'W1'},
        ],
      });

      final line = inv.items.first;
      expect(line.quantity, 1.0);
      expect(line.rate, 0.0);
      expect(line.taxPercentage, 0.0);
      expect(line.discount, 0.0);
    });
  });
}
