import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/item_model.dart';
import 'package:van_sales/data/models/sales_invoice_model.dart';
import 'package:van_sales/data/models/sales_order_model.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';

void main() {
  group('ItemModel tax_id', () {
    test('parses tax_id from Zoho item JSON', () {
      final item = ItemModel.fromJson({
        'item_id': '3331482000002275246',
        'name': 'NELLON JEERAKASHALA',
        'sku': 'SKU1',
        'rate': 120,
        'stock_on_hand': 10,
        'tax_id': '3331482000000075238',
        'tax_name': 'Standard Rate',
        'tax_percentage': 5,
        'unit': 'pcs',
      });

      expect(item.taxId, '3331482000000075238');
      expect(item.taxName, 'Standard Rate');
      expect(item.taxPercentage, 5);
      expect(item.toJson()['tax_id'], '3331482000000075238');
    });

    test('does not invent VAT 5% when tax fields absent', () {
      final item = ItemModel.fromJson({
        'item_id': 'i1',
        'name': 'X',
        'rate': 1,
      });
      expect(item.taxId, isEmpty);
      expect(item.taxName, isEmpty);
      expect(item.taxPercentage, 0);
    });
  });

  group('Line item tax_id serialization', () {
    const item = Item(
      id: 'i1',
      name: 'Product',
      sku: 'S1',
      rate: 100,
      stock: 5,
      description: '',
      taxId: '3331482000000075238',
      taxName: 'Standard Rate',
      taxPercentage: 5,
    );

    test('order line toJson includes tax_id', () {
      final line = OrderLineItemModel.fromDomain(
        const OrderLineItem(
          item: item,
          quantity: 2,
          rate: 100,
          taxPercentage: 5,
        ),
      );
      final json = line.toJson();
      expect(json['tax_id'], '3331482000000075238');
      expect(json['tax_percentage'], 5);
      expect(json['item']['tax_id'], '3331482000000075238');
    });

    test('invoice line toJson includes tax_id', () {
      final line = InvoiceLineItemModel.fromDomain(
        const InvoiceLineItem(
          item: item,
          quantity: 1,
          rate: 100,
          taxPercentage: 5,
        ),
      );
      expect(line.toJson()['tax_id'], '3331482000000075238');
    });

    test('invoice line persists Zoho line_item_id', () {
      final line = InvoiceLineItemModel.fromJson({
        'item_id': 'i1',
        'name': 'Product',
        'quantity': 1,
        'rate': 100,
        'line_item_id': 'zoho_line_9',
      });
      expect(line.lineItemId, 'zoho_line_9');
      expect(line.toJson()['line_item_id'], 'zoho_line_9');
    });

    test('order line fromJson merges line-level tax_id onto item', () {
      final line = OrderLineItemModel.fromJson({
        'item_id': 'i1',
        'name': 'Product',
        'quantity': 1,
        'rate': 100,
        'tax_id': '3331482000000075238',
        'tax_name': 'Standard Rate',
        'tax_percentage': 5,
      });
      expect(line.item.taxId, '3331482000000075238');
      expect(line.item.taxName, 'Standard Rate');
      expect(line.taxPercentage, 5);
    });
  });
}
