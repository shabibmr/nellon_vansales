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
        'billing_address': {'address': 'Street 1', 'latitude': 1.1, 'longitude': 2.2},
        'credit_limit': 500,
        'outstandingBalance': 42.0,
        'route_id': 'r1',
        'sequence': 3,
        'isPendingSync': true,
        'latitude': 1.1,
        'longitude': 2.2,
      };

      final out = ZohoPayloadMapper.zohoContactPayload(raw);

      expect(out.keys, containsAll(['contact_name', 'company_name', 'billing_address']));
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('contact_id'), isFalse);
      expect(out.containsKey('name'), isFalse);
      expect(out.containsKey('outstandingBalance'), isFalse);
      expect(out.containsKey('route_id'), isFalse);
      expect(out.containsKey('sequence'), isFalse);
      expect(out.containsKey('isPendingSync'), isFalse);
      expect(out.containsKey('latitude'), isFalse);
      expect(out.containsKey('longitude'), isFalse);
      // GPS survives via billing_address
      expect((out['billing_address'] as Map)['latitude'], 1.1);
      expect((out['billing_address'] as Map)['longitude'], 2.2);
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
        'zoho_invoice_id': 'zoho_inv_1',
        'round_off': 0.0,
        'location_id': 'loc_1',
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 2,
            'rate': 10.0,
            'tax_id': 'tax_std',
            'tax_percentage': 5.0,
            'discount': 0.0,
            'item': {
              'id': 'item_1',
              'sku': 'SKU1',
              'stock_on_hand': 99,
              'tax_id': 'tax_std',
            },
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
      expect(out.containsKey('zoho_invoice_id'), isFalse);
      expect(out.containsKey('round_off'), isFalse);

      final line = (out['line_items'] as List).first as Map;
      expect(line['item_id'], 'item_1');
      expect(line['quantity'], 2);
      expect(line['tax_id'], 'tax_std');
      expect(line.containsKey('item'), isFalse);
    });

    test('lifts tax_id from nested item when line-level missing', () {
      final out = ZohoPayloadMapper.zohoInvoicePayload({
        'customer_id': 'c1',
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 1,
            'rate': 10.0,
            'tax_percentage': 5.0,
            'item': {'id': 'item_1', 'tax_id': 'tax_from_item'},
          },
        ],
      });
      expect((out['line_items'] as List).first['tax_id'], 'tax_from_item');
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
            'tax_id': 'tax_std',
            'tax_percentage': 5.0,
            'discount': 1.0,
            'item': {'id': 'item_1', 'name': 'X', 'tax_id': 'tax_std'},
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
      expect(line['tax_id'], 'tax_std');
    });
  });

  group('withResolvedLineTaxIds', () {
    /// Mirrors [ZohoApiClient._withResolvedLineTaxIds] resolution policy:
    /// pct &gt; 0 → match rate; else default Standard Rate (never Zero Rate via 0%).
    String? resolveLikeApi(double? pct) {
      if (pct != null && pct > 0) {
        if ((pct - 5.0).abs() < 0.001) return 'tax_standard';
      }
      return 'tax_standard'; // default is_default_tax
    }

    test('fills missing tax_id from resolveTaxId by percentage', () {
      final out = ZohoPayloadMapper.withResolvedLineTaxIds(
        {
          'line_items': [
            {'item_id': 'i1', 'tax_percentage': 5.0},
            {'item_id': 'i2', 'tax_id': 'keep_me', 'tax_percentage': 0},
          ],
        },
        resolveTaxId: (pct) => pct == 5.0 ? 'tax_5' : 'tax_default',
      );
      final lines = out['line_items'] as List;
      expect(lines[0]['tax_id'], 'tax_5');
      expect(lines[1]['tax_id'], 'keep_me');
    });

    test('missing tax_id with pct 5 resolves to Standard Rate id', () {
      final out = ZohoPayloadMapper.withResolvedLineTaxIds(
        {
          'line_items': [
            {'item_id': 'i1', 'quantity': 1, 'rate': 10, 'tax_percentage': 5.0},
          ],
        },
        resolveTaxId: resolveLikeApi,
      );
      expect((out['line_items'] as List).first['tax_id'], 'tax_standard');
    });

    test('missing tax_id with pct 0/null falls back to default Standard Rate', () {
      final out = ZohoPayloadMapper.withResolvedLineTaxIds(
        {
          'line_items': [
            {'item_id': 'i1', 'tax_percentage': 0},
            {'item_id': 'i2'},
          ],
        },
        resolveTaxId: resolveLikeApi,
      );
      final lines = out['line_items'] as List;
      expect(lines[0]['tax_id'], 'tax_standard');
      expect(lines[1]['tax_id'], 'tax_standard');
    });

    test('keeps explicit Zero Rate tax_id unchanged', () {
      final out = ZohoPayloadMapper.withResolvedLineTaxIds(
        {
          'line_items': [
            {
              'item_id': 'i1',
              'tax_id': 'tax_zero',
              'tax_percentage': 0,
            },
          ],
        },
        resolveTaxId: resolveLikeApi,
      );
      expect((out['line_items'] as List).first['tax_id'], 'tax_zero');
    });

    test('strips residual tax_exemption keys when resolving', () {
      final out = ZohoPayloadMapper.withResolvedLineTaxIds(
        {
          'line_items': [
            {
              'item_id': 'i1',
              'tax_percentage': 5.0,
              'tax_exemption_id': 'ex_1',
              'tax_exemption_code': 'EXEMPT',
            },
          ],
        },
        resolveTaxId: resolveLikeApi,
      );
      final line = (out['line_items'] as List).first as Map;
      expect(line['tax_id'], 'tax_standard');
      expect(line.containsKey('tax_exemption_id'), isFalse);
      expect(line.containsKey('tax_exemption_code'), isFalse);
    });

    test('invoice/SO/credit-note cleaned lines keep resolved tax_id', () {
      final line = <String, dynamic>{
        'item_id': 'item_1',
        'quantity': 1,
        'rate': 10.0,
        'tax_id': 'tax_standard',
        'tax_percentage': 5.0,
      };
      final withTax = {
        'customer_id': 'c1',
        'line_items': [line],
      };
      for (final out in [
        ZohoPayloadMapper.zohoInvoicePayload(withTax),
        ZohoPayloadMapper.zohoSalesOrderPayload(withTax),
        ZohoPayloadMapper.zohoCreditNotePayload({
          'customer_id': 'c1',
          'line_items': [
            {...line, 'invoice_id': 'inv_1'},
          ],
        }),
      ]) {
        expect((out['line_items'] as List).first['tax_id'], 'tax_standard');
      }
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
            'tax_id': 'tax_std',
            'tax_percentage': 5.0,
            'invoice_id': 'inv_1',
            'invoice_number': 'INV-1',
            'invoiceLineItem': {
              'item_id': 'item_1',
              'item': {'id': 'item_1', 'tax_id': 'tax_std'},
            },
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoCreditNotePayload(raw);

      expect(out['creditnote_number'], 'CN-1');
      expect(out['notes'], 'damaged');
      expect(out.containsKey('reason'), isFalse);
      expect(out.containsKey('reason_for_credit_debit_note'), isFalse);
      for (final k in ['id', 'creditnote_id', 'customer_name', 'isPendingSync']) {
        expect(out.containsKey(k), isFalse, reason: 'should drop $k');
      }
      final line = (out['line_items'] as List).first as Map;
      expect(line['item_id'], 'item_1');
      expect(line['invoice_id'], 'inv_1');
      expect(line['tax_id'], 'tax_std');
      expect(line.containsKey('invoice_number'), isFalse);
      expect(line.containsKey('invoiceLineItem'), isFalse);
    });

    test('maps empty reason to no notes', () {
      final out = ZohoPayloadMapper.zohoCreditNotePayload({
        'customer_id': 'c1',
        'reason': '',
        'line_items': const <dynamic>[],
      });
      expect(out.containsKey('notes'), isFalse);
      expect(out.containsKey('reason'), isFalse);
    });

    test('forwards invoice_item_id from a returned invoice line', () {
      final out = ZohoPayloadMapper.zohoCreditNotePayload({
        'customer_id': 'c1',
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 1,
            'rate': 10.0,
            'invoice_id': 'inv_1',
            'invoice_item_id': 'line_zoho_1',
          },
        ],
      });
      expect((out['line_items'] as List).first['invoice_item_id'], 'line_zoho_1');
    });

    test('lifts tax_id from nested invoiceLineItem.item', () {
      final out = ZohoPayloadMapper.zohoCreditNotePayload({
        'customer_id': 'c1',
        'line_items': [
          {
            'item_id': 'item_1',
            'quantity': 1,
            'rate': 10.0,
            'invoice_id': 'inv_1',
            'invoiceLineItem': {
              'item': {'id': 'item_1', 'tax_id': 'tax_nested'},
            },
          },
        ],
      });
      expect((out['line_items'] as List).first['tax_id'], 'tax_nested');
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

      expect(out.containsKey('transfer_order_number'), isFalse);
      expect(out['from_location_id'], 'loc_wh');
      expect(out['to_location_id'], 'loc_van');
      // notes mapped to description
      expect(out['description'], 'issue to van');
      expect(out.containsKey('notes'), isFalse);
      for (final k in [
        'id',
        'transfer_order_id',
        'direction',
        'isPendingSync',
        'zoho_transfer_id',
        'location_id',
      ]) {
        expect(out.containsKey(k), isFalse, reason: 'should drop $k');
      }
      final line = (out['line_items'] as List).first as Map;
      expect(line['item_id'], 'item_1');
      expect(line['name'], 'Item One');
      expect(line['quantity_transfer'], 5);
      expect(line.containsKey('quantity'), isFalse);
      expect(line.containsKey('item'), isFalse);
    });

    test('drops local TO-TEMP transfer_order_number from queued model JSON', () {
      final raw = {
        'id': 'temp_to_1',
        'transfer_order_id': 'temp_to_1',
        'transfer_order_number': 'TO-TEMP-123456',
        'date': '2026-08-14',
        'direction': 'load',
        'from_location_id': 'loc_wh',
        'to_location_id': 'loc_van',
        'notes': '',
        'isPendingSync': true,
        'line_items': [
          {
            'item_id': 'item_1',
            'name': 'Rice',
            'quantity_transfer': 1,
            'quantity': 1,
          },
        ],
      };

      final out = ZohoPayloadMapper.zohoStockTransferPayload(raw);
      expect(out.containsKey('transfer_order_number'), isFalse);
      expect(out['from_location_id'], 'loc_wh');
      expect(out['to_location_id'], 'loc_van');
      expect(out.containsKey('description'), isFalse);
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
      expect(out.containsKey('is_inclusive_tax'), isFalse);

      final items = out['line_items'] as List;
      expect(items, hasLength(2));
      expect((items.first as Map)['account_id'], 'acc_fuel');
      expect((items.first as Map)['amount'], 30.0);
      expect((items[1] as Map)['account_id'], 'acc_toll');
    });

    test('forwards Fuel tax_id and sets inclusive tax', () {
      final out = ZohoPayloadMapper.zohoExpensePayload(
        {'date': '2026-07-06'},
        resolvedLines: [
          {
            'account_id': 'acc_fuel',
            'amount': 120.0,
            'description': 'Diesel',
            'tax_id': 'tax_standard',
          },
          {
            'account_id': 'acc_park',
            'amount': 10.0,
            'description': 'Mall',
          },
        ],
        paidThroughAccountId: 'acc_cash',
        isInclusiveTax: true,
      );

      expect(out['is_inclusive_tax'], isTrue);
      expect(out['amount'], 130.0);
      final items = out['line_items'] as List;
      expect((items[0] as Map)['tax_id'], 'tax_standard');
      expect((items[1] as Map).containsKey('tax_id'), isFalse);
    });
  });
}
