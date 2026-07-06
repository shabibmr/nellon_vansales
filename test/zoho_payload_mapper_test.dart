import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/zoho_payload_mapper.dart';

/// The input maps below mirror the exact shape produced by each
/// `Model.toJson()` (verified against lib/data/models/*.dart) — i.e. the payload
/// that gets stored in the Hive sync queue and later handed to `ZohoApiClient`.
void main() {
  group('zohoContactPayload', () {
    test('keeps Zoho contact fields, drops local + root GPS keys', () {
      final raw = {
        'id': 'local_1',
        'contact_id': 'temp_1',
        'name': 'ACME',
        'contact_name': 'ACME',
        'company_name': 'ACME Ltd',
        'email': 'a@b.com',
        'phone': '123',
        'billing_address': {'address': 'Street 1'},
        'credit_limit': 500,
        'outstandingBalance': 42.0,
        'route_id': 'r1',
        'sequence': 3,
        'isPendingSync': true,
        'latitude': 1.1,
        'longitude': 2.2,
        'custom_fields': [
          {'api_name': 'cf_latitude', 'value': '1.1'},
          {'api_name': 'cf_longitude', 'value': '2.2'},
        ],
      };

      final out = ZohoPayloadMapper.zohoContactPayload(raw);

      expect(out.keys, containsAll(['contact_name', 'company_name', 'custom_fields']));
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('contact_id'), isFalse);
      expect(out.containsKey('name'), isFalse);
      expect(out.containsKey('outstandingBalance'), isFalse);
      expect(out.containsKey('route_id'), isFalse);
      expect(out.containsKey('sequence'), isFalse);
      expect(out.containsKey('isPendingSync'), isFalse);
      expect(out.containsKey('latitude'), isFalse);
      expect(out.containsKey('longitude'), isFalse);
      // GPS survives via custom_fields
      expect(out['custom_fields'], hasLength(2));
    });
  });

  group('zohoInvoicePayload', () {
    test('keeps invoice fields, strips local root keys and nested item', () {
      final raw = {
        'id': 'inv_local',
        'invoice_id': 'inv_local',
        'invoice_number': 'INV-1',
        'customer_id': 'cust_1',
        'customer_name': 'ACME',
        'date': '2026-07-06',
        'due_date': '2026-07-20',
        'notes': 'thanks',
        'isPendingSync': true,
        'round_off': 0.0,
        'location_id': 'loc_1',
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 2,
            'rate': 10.0,
            'tax_percentage': 5.0,
            'discount': 0.0,
            'item': {'id': 'item_1', 'sku': 'SKU1', 'stock_on_hand': 99},
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoInvoicePayload(raw);

      expect(out['customer_id'], 'cust_1');
      expect(out['invoice_number'], 'INV-1');
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('invoice_id'), isFalse);
      expect(out.containsKey('customer_name'), isFalse);
      expect(out.containsKey('isPendingSync'), isFalse);
      expect(out.containsKey('round_off'), isFalse);

      final line = (out['line_items'] as List).first as Map;
      expect(line['item_id'], 'item_1');
      expect(line['quantity'], 2);
      expect(line.containsKey('item'), isFalse);
    });
  });

  group('zohoSalesOrderPayload', () {
    test('keeps order fields, strips local keys and nested item', () {
      final raw = {
        'id': 'so_local',
        'salesorder_id': 'so_local',
        'salesorder_number': 'SO-1',
        'customer_id': 'cust_1',
        'customer_name': 'ACME',
        'date': '2026-07-06',
        'shipment_date': '2026-07-10',
        'notes': 'note',
        'isPendingSync': true,
        'round_off': 0.0,
        'status': 'open',
        'converted_invoice_number': null,
        'zoho_order_id': null,
        'location_id': 'loc_1',
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 3,
            'rate': 20.0,
            'tax_percentage': 5.0,
            'discount': 1.0,
            'item': {'id': 'item_1', 'name': 'X'},
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoSalesOrderPayload(raw);

      expect(out['salesorder_number'], 'SO-1');
      for (final k in [
        'id',
        'salesorder_id',
        'customer_name',
        'isPendingSync',
        'round_off',
        'status',
        'converted_invoice_number',
        'zoho_order_id',
      ]) {
        expect(out.containsKey(k), isFalse, reason: 'should drop $k');
      }
      final line = (out['line_items'] as List).first as Map;
      expect(line.containsKey('item'), isFalse);
      expect(line['discount'], 1.0);
    });
  });

  group('zohoReceiptPayload', () {
    test('keeps payment fields, strips local keys and invoice_number', () {
      final raw = {
        'id': 'pay_local',
        'payment_id': 'pay_local',
        'payment_number': 'PAY-1',
        'customer_id': 'cust_1',
        'customer_name': 'ACME',
        'amount': 100.0,
        'payment_mode': 'Cash',
        'reference_number': 'R1',
        'date': '2026-07-06',
        'isPendingSync': true,
        'location_id': 'loc_1',
        'invoices': [
          {
            'invoice_id': 'inv_1',
            'invoice_number': 'INV-1',
            'amount_applied': 100.0,
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoReceiptPayload(raw);

      expect(out['payment_mode'], 'Cash');
      expect(out['amount'], 100.0);
      for (final k in ['id', 'payment_id', 'payment_number', 'customer_name', 'isPendingSync']) {
        expect(out.containsKey(k), isFalse, reason: 'should drop $k');
      }
      final alloc = (out['invoices'] as List).first as Map;
      expect(alloc['invoice_id'], 'inv_1');
      expect(alloc['amount_applied'], 100.0);
      expect(alloc.containsKey('invoice_number'), isFalse);
    });
  });

  group('zohoCreditNotePayload', () {
    test('keeps credit note fields, strips local + nested invoiceLineItem', () {
      final raw = {
        'id': 'cn_local',
        'creditnote_id': 'cn_local',
        'creditnote_number': 'CN-1',
        'customer_id': 'cust_1',
        'customer_name': 'ACME',
        'date': '2026-07-06',
        'location_id': 'loc_1',
        'reason': 'damaged',
        'isPendingSync': true,
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 1,
            'rate': 10.0,
            'invoice_id': 'inv_1',
            'invoice_number': 'INV-1',
            'invoiceLineItem': {'item_id': 'item_1', 'item': {'id': 'item_1'}},
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoCreditNotePayload(raw);

      expect(out['creditnote_number'], 'CN-1');
      expect(out['reason'], 'damaged');
      for (final k in ['id', 'creditnote_id', 'customer_name', 'isPendingSync']) {
        expect(out.containsKey(k), isFalse, reason: 'should drop $k');
      }
      final line = (out['line_items'] as List).first as Map;
      expect(line['item_id'], 'item_1');
      expect(line['invoice_id'], 'inv_1');
      expect(line.containsKey('invoice_number'), isFalse);
      expect(line.containsKey('invoiceLineItem'), isFalse);
    });
  });

  group('zohoStockTransferPayload', () {
    test('maps notes->description, uses quantity_transfer, drops local keys', () {
      final raw = {
        'id': 'to_local',
        'transfer_order_id': 'to_local',
        'transfer_order_number': 'TO-1',
        'date': '2026-07-06',
        'direction': 'load',
        'from_location_id': 'loc_wh',
        'to_location_id': 'loc_van',
        'notes': 'issue to van',
        'isPendingSync': true,
        'zoho_transfer_id': null,
        'location_id': 'loc_van',
        'line_items': [
          {
            'item_id': 'item_1',
            'name': 'Item One',
            'quantity_transfer': 5,
            'quantity': 5,
            'item': {'id': 'item_1', 'sku': 'SKU1'},
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoStockTransferPayload(raw);

      expect(out['transfer_order_number'], 'TO-1');
      expect(out['from_location_id'], 'loc_wh');
      expect(out['to_location_id'], 'loc_van');
      // notes mapped to description
      expect(out['description'], 'issue to van');
      expect(out.containsKey('notes'), isFalse);
      for (final k in ['id', 'transfer_order_id', 'direction', 'isPendingSync', 'zoho_transfer_id', 'location_id']) {
        expect(out.containsKey(k), isFalse, reason: 'should drop $k');
      }
      final line = (out['line_items'] as List).first as Map;
      expect(line['item_id'], 'item_1');
      expect(line['name'], 'Item One');
      expect(line['quantity_transfer'], 5);
      expect(line.containsKey('quantity'), isFalse);
      expect(line.containsKey('item'), isFalse);
    });
  });

  group('zohoExpensePayload', () {
    test('builds itemized line_items with per-line accounts + cash payer', () {
      final raw = {
        'id': 'exp_local',
        'expense_id': 'exp_local',
        'date': '2026-07-06',
        'receiptImagePath': null,
        'isPendingSync': true,
        'location_id': 'loc_1',
        'reference_number': 'REF-1',
        'lines': [
          {'category': 'Fuel', 'amount': 30.0, 'description': 'Diesel'},
          {'category': 'Tolls', 'amount': 12.5, 'description': 'Highway'},
        ],
      };
      final resolvedLines = [
        {'account_id': 'acc_fuel', 'amount': 30.0, 'description': 'Diesel'},
        {'account_id': 'acc_toll', 'amount': 12.5, 'description': 'Highway'},
      ];

      final out = ZohoPayloadMapper.zohoExpensePayload(
        raw,
        resolvedLines: resolvedLines,
        paidThroughAccountId: 'acc_cash',
      );

      expect(out['date'], '2026-07-06');
      expect(out['amount'], 42.5);
      expect(out['paid_through_account_id'], 'acc_cash');
      // root account_id satisfies the schema with the first line's account
      expect(out['account_id'], 'acc_fuel');
      expect(out['reference_number'], 'REF-1');
      // non-standard local structure gone
      expect(out.containsKey('lines'), isFalse);
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('isPendingSync'), isFalse);

      final items = out['line_items'] as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['account_id'], 'acc_fuel');
      expect((items.first as Map)['amount'], 30.0);
      expect((items[1] as Map)['account_id'], 'acc_toll');
    });
  });
}
