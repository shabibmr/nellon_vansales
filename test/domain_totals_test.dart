import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';

void main() {
  const item1 = Item(
    id: 'item_1',
    name: 'Item One',
    sku: 'SKU1',
    rate: 10.50,
    stock: 10,
    description: 'First item',
    taxName: 'VAT 5%',
    taxPercentage: 5.0,
  );

  const item2 = Item(
    id: 'item_2',
    name: 'Item Two',
    sku: 'SKU2',
    rate: 20.00,
    stock: 5,
    description: 'Second item',
    taxName: 'VAT 10%',
    taxPercentage: 10.0,
  );

  group('InvoiceLineItem & SalesInvoice calculations', () {
    test('line item calculations with discount and modified rate', () {
      const line = InvoiceLineItem(
        item: item1,
        quantity: 3,
        rate: 12.00, // changed rate
        taxPercentage: 5.0,
        discount: 2.00, // custom discount
      );

      // subtotal = rate * quantity = 12 * 3 = 36
      expect(line.subTotal, equals(36.00));

      // taxAmount = (subtotal) * 5% = 36 * 0.05 = 1.80
      expect(line.taxAmount, equals(1.80));

      // total = subtotal + taxAmount - discount = 36.0 + 1.80 - 2.00 = 35.80
      expect(line.total, equals(35.80));
    });

    test('invoice rounding to nearest integer', () {
      const line1 = InvoiceLineItem(
        item: item1,
        quantity: 2, // subtotal = 21.00, tax (5%) = 1.05, total = 22.05
        rate: 10.50,
        taxPercentage: 5.0,
      );

      const line2 = InvoiceLineItem(
        item: item2,
        quantity: 1, // subtotal = 20.00, tax (10%) = 2.00, total = 22.00
        rate: 20.00,
        taxPercentage: 10.0,
        discount: 1.50, // total = 20.0 + 2.0 - 1.50 = 20.50
      );

      final invoice = SalesInvoice(
        id: 'inv_1',
        invoiceNumber: 'INV-1',
        customerId: 'cust_1',
        customerName: 'Customer One',
        date: DateTime.now(),
        dueDate: DateTime.now(),
        items: const [line1, line2],
        notes: '',
      );

      // subTotal = 21.00 + 20.00 = 41.00
      expect(invoice.subTotal, equals(41.00));

      // taxTotal = 1.05 + 2.00 = 3.05
      expect(invoice.taxTotal, equals(3.05));

      // discountTotal = 0.0 + 1.50 = 1.50
      expect(invoice.discountTotal, equals(1.50));

      // rawTotal = 22.05 + 20.50 = 42.55
      expect(invoice.rawTotal, equals(42.55));

      // total (rounded to nearest integer) = 43.0
      expect(invoice.total, equals(43.00));

      // roundOff = total - rawTotal = 43.00 - 42.55 = 0.45
      expect(invoice.roundOff, closeTo(0.45, 0.0001));
    });
  });

  group('OrderLineItem & SalesOrder calculations', () {
    test('sales order rounding to nearest integer', () {
      const line1 = OrderLineItem(
        item: item1,
        quantity: 2, // subtotal = 21.00, tax (5%) = 1.05, total = 22.05
        rate: 10.50,
        taxPercentage: 5.0,
      );

      const line2 = OrderLineItem(
        item: item2,
        quantity: 1, // subtotal = 20.00, tax (10%) = 2.00, total = 22.00
        rate: 20.00,
        taxPercentage: 10.0,
        discount: 1.60, // total = 20.0 + 2.0 - 1.60 = 20.40
      );

      final order = SalesOrder(
        id: 'so_1',
        orderNumber: 'SO-1',
        customerId: 'cust_1',
        customerName: 'Customer One',
        date: DateTime.now(),
        shipmentDate: DateTime.now(),
        items: const [line1, line2],
        notes: '',
      );

      // subTotal = 21.00 + 20.00 = 41.00
      expect(order.subTotal, equals(41.00));

      // taxTotal = 1.05 + 2.00 = 3.05
      expect(order.taxTotal, equals(3.05));

      // discountTotal = 0.0 + 1.60 = 1.60
      expect(order.discountTotal, equals(1.60));

      // rawTotal = 22.05 + 20.40 = 42.45
      expect(order.rawTotal, equals(42.45));

      // total (rounded to nearest integer) = 42.0
      expect(order.total, equals(42.00));

      // roundOff = total - rawTotal = 42.00 - 42.45 = -0.45
      expect(order.roundOff, closeTo(-0.45, 0.0001));
    });
  });

  group('SalesReturnLineItem total (tax + prorated discount)', () {
    test('full-quantity return includes tax and the full original discount', () {
      // Original invoiced line: 10 units @ 12.00, 5% tax, 5.00 total discount.
      const originalLine = InvoiceLineItem(
        item: item1,
        quantity: 10,
        rate: 12.00,
        taxPercentage: 5.0,
        discount: 5.00,
      );

      const returnLine = SalesReturnLineItem(
        invoiceLineItem: originalLine,
        returnedQuantity: 10,
      );

      // subTotal = 12.00 * 10 = 120.00
      expect(returnLine.subTotal, equals(120.00));
      // taxAmount = 120.00 * 5% = 6.00
      expect(returnLine.taxAmount, equals(6.00));
      // Full return -> full original discount credited back.
      expect(returnLine.discountAmount, equals(5.00));
      // total = 120.00 + 6.00 - 5.00 = 121.00
      expect(returnLine.total, equals(121.00));
    });

    test('partial-quantity return prorates tax and discount', () {
      // Original invoiced line: 10 units @ 12.00, 5% tax, 5.00 total discount.
      const originalLine = InvoiceLineItem(
        item: item1,
        quantity: 10,
        rate: 12.00,
        taxPercentage: 5.0,
        discount: 5.00,
      );

      // Only 2 of the 10 units are being returned.
      const returnLine = SalesReturnLineItem(
        invoiceLineItem: originalLine,
        returnedQuantity: 2,
      );

      // subTotal = 12.00 * 2 = 24.00
      expect(returnLine.subTotal, equals(24.00));
      // taxAmount = 24.00 * 5% = 1.20
      expect(returnLine.taxAmount, equals(1.20));
      // discountAmount = (5.00 / 10) * 2 = 1.00 (prorated, not the full 5.00)
      expect(returnLine.discountAmount, equals(1.00));
      // total = 24.00 + 1.20 - 1.00 = 24.20
      expect(returnLine.total, equals(24.20));
    });
  });

  group('Floating-point drift guard (roundMoney)', () {
    test('summing many binary-imprecise line totals stays exact to the cent', () {
      // 0.1 is not exactly representable in binary floating point; summing it
      // 30 times via raw double addition drifts off the cent (e.g. 3.0000000000000004).
      const rateItem = Item(
        id: 'item_3',
        name: 'Cheap Item',
        sku: 'SKU3',
        rate: 0.1,
        stock: 100,
        description: 'Sub-cent-drift item',
        taxName: 'No Tax',
        taxPercentage: 0.0,
      );

      final lines = List.generate(
        30,
        (_) => const InvoiceLineItem(
          item: rateItem,
          quantity: 1,
          rate: 0.1,
          taxPercentage: 0.0,
        ),
      );

      final invoice = SalesInvoice(
        id: 'inv_drift',
        invoiceNumber: 'INV-DRIFT',
        customerId: 'cust_1',
        customerName: 'Customer One',
        date: DateTime.now(),
        dueDate: DateTime.now(),
        items: lines,
        notes: '',
      );

      // Without rounding at each accumulation step, raw double summation of
      // 0.1 x 30 produces 3.0000000000000004 instead of exactly 3.0.
      expect(invoice.subTotal, equals(3.0));
      expect(invoice.rawTotal, equals(3.0));
    });
  });
}
