import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sales_order_model.dart';
import 'package:van_sales/data/models/sales_return_model.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';

void main() {
  group('SalesOrderModel header vs detail', () {
    test('header JSON maps status and listedTotal without line items', () {
      final order = SalesOrderModel.fromJson({
        'salesorder_id': 'so_1',
        'salesorder_number': 'SO-001',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'shipment_date': '2026-03-02',
        'status': 'open',
        'total': 1500.5,
      });

      expect(order.id, 'so_1');
      expect(order.status, SalesOrderStatus.open);
      expect(order.listedTotal, 1500.5);
      expect(order.items, isEmpty);
      expect(order.total, 1501.0);
    });

    test('header maps order_status, invoiced_status, reference_number', () {
      // Shape mirrors live GET /salesorders?salesperson_id=… list row.
      final order = SalesOrderModel.fromJson({
        'salesorder_id': '3331482000182099001',
        'salesorder_number': 'SHF-SO-00007',
        'customer_id': '3331482000182087001',
        'customer_name': 'Test Customer',
        'date': '2026-08-05',
        'shipment_date': '2026-08-06',
        'status': 'draft',
        'order_status': 'draft',
        'invoiced_status': '',
        'reference_number': 'PO-99',
        'total': 170.0,
      });

      expect(order.orderStatus, 'draft');
      expect(order.invoicedStatus, '');
      expect(order.referenceNumber, 'PO-99');
      expect(order.status, SalesOrderStatus.open); // draft → open enum

      final hive = SalesOrderModel.fromDomain(order).toJson();
      expect(hive['order_status'], 'draft');
      expect(hive['invoiced_status'], '');
      expect(hive['reference_number'], 'PO-99');

      final roundTrip = SalesOrderModel.fromJson(hive);
      expect(roundTrip.orderStatus, 'draft');
      expect(roundTrip.referenceNumber, 'PO-99');
    });

    test('order_status invoiced drives domain status and isConverted', () {
      final order = SalesOrderModel.fromJson({
        'salesorder_id': 'so_inv',
        'salesorder_number': 'SO-INV',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-08-05',
        'status': 'open',
        'order_status': 'invoiced',
        'invoiced_status': 'invoiced',
        'total': 10.0,
      });
      expect(order.orderStatus, 'invoiced');
      expect(order.invoicedStatus, 'invoiced');
      expect(order.status, SalesOrderStatus.invoiced);
      expect(order.isConverted, isTrue);
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
      final order = SalesOrder(
        id: 'so_2',
        orderNumber: 'SO-002',
        customerId: 'c1',
        customerName: 'Acme',
        date: DateTime(2026, 3, 1),
        shipmentDate: DateTime(2026, 3, 2),
        items: const [
          OrderLineItem(
            item: item,
            quantity: 2,
            rate: 10,
            taxPercentage: 0,
          ),
        ],
        notes: '',
        listedTotal: 9999,
      );

      expect(order.total, 20.0);
    });
  });

  group('SalesReturnModel header vs detail', () {
    test('header JSON maps listedTotal without line items', () {
      final ret = SalesReturnModel.fromJson({
        'creditnote_id': 'cn_1',
        'creditnote_number': 'CN-001',
        'customer_id': 'c1',
        'customer_name': 'Acme',
        'date': '2026-03-01',
        'total': 250.25,
      });

      expect(ret.id, 'cn_1');
      expect(ret.listedTotal, 250.25);
      expect(ret.items, isEmpty);
      expect(ret.total, 250.25);
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
      final ret = SalesReturn(
        id: 'cn_2',
        creditNoteNumber: 'CN-002',
        customerId: 'c1',
        customerName: 'Acme',
        date: DateTime(2026, 3, 1),
        items: [
          SalesReturnLineItem(
            invoiceLineItem: InvoiceLineItem(
              item: item,
              quantity: 5,
              rate: 10,
              taxPercentage: 0,
            ),
            returnedQuantity: 2,
          ),
        ],
        reason: '',
        listedTotal: 9999,
      );

      expect(ret.total, 20.0);
    });
  });
}
