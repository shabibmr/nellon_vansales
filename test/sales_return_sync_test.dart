import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/sales_return_sync.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/data/models/sales_return_model.dart';

const _item = Item(
  id: 'item_1',
  name: 'Rice',
  sku: 'SKU1',
  rate: 100,
  stock: 10,
  description: '',
  taxName: 'VAT',
  taxPercentage: 5,
);

void main() {
  group('SalesReturnSync.existingRemoteId', () {
    test('reads zoho_credit_note_id and ignores local temp / creditnote_id', () {
      expect(
        SalesReturnSync.existingRemoteId({
          'id': 'temp_ret_1',
          'creditnote_id': 'temp_ret_1',
        }),
        isNull,
      );
      expect(
        SalesReturnSync.existingRemoteId({
          'zoho_credit_note_id': 'temp_ret_1',
        }),
        isNull,
      );
      expect(
        SalesReturnSync.existingRemoteId({
          'id': 'temp_ret_1',
          'zoho_credit_note_id': '3331482000180093168',
        }),
        '3331482000180093168',
      );
    });
  });

  group('SalesReturnSync.sharedInvoiceId', () {
    test('returns the invoice id when every line agrees', () {
      expect(
        SalesReturnSync.sharedInvoiceId({
          'line_items': [
            {'invoice_id': 'inv_1'},
            {'invoice_id': 'inv_1'},
          ],
        }),
        'inv_1',
      );
    });

    test('returns null when lines disagree or still use temp ids', () {
      expect(
        SalesReturnSync.sharedInvoiceId({
          'line_items': [
            {'invoice_id': 'inv_1'},
            {'invoice_id': 'inv_2'},
          ],
        }),
        isNull,
      );
      expect(
        SalesReturnSync.sharedInvoiceId({
          'line_items': [
            {'invoice_id': 'temp_inv_1'},
          ],
        }),
        isNull,
      );
      expect(SalesReturnSync.sharedInvoiceId({'line_items': <dynamic>[]}), isNull);
    });
  });

  group('SalesReturnSync.applyInvoices', () {
    test('groups domain line totals by invoice_id', () {
      final ret = SalesReturn(
        id: 'temp_ret_1',
        creditNoteNumber: 'CN-1',
        customerId: 'cust_1',
        customerName: 'Acme',
        date: DateTime(2026, 6, 8),
        reason: 'damaged',
        items: const [
          SalesReturnLineItem(
            invoiceLineItem: InvoiceLineItem(
              item: _item,
              quantity: 1,
              rate: 130,
              taxPercentage: 5,
            ),
            returnedQuantity: 1,
            invoiceId: 'inv_1',
          ),
        ],
      );

      final rows = SalesReturnSync.applyInvoices(
        SalesReturnModel.fromDomain(ret).toJson(),
      );
      expect(rows, hasLength(1));
      expect(rows.single['invoice_id'], 'inv_1');
      // 130 + 5% VAT = 136.5
      expect(rows.single['amount_applied'], 136.5);
    });

    test('skips temp invoice ids', () {
      final ret = SalesReturn(
        id: 'temp_ret_1',
        creditNoteNumber: 'CN-1',
        customerId: 'cust_1',
        customerName: 'Acme',
        date: DateTime(2026, 6, 8),
        reason: '',
        items: const [
          SalesReturnLineItem(
            invoiceLineItem: InvoiceLineItem(
              item: _item,
              quantity: 1,
              rate: 10,
              taxPercentage: 0,
            ),
            returnedQuantity: 1,
            invoiceId: 'temp_inv_9',
          ),
        ],
      );
      expect(
        SalesReturnSync.applyInvoices(SalesReturnModel.fromDomain(ret).toJson()),
        isEmpty,
      );
    });
  });

  group('SalesReturnSync.alreadyApplied', () {
    test('true when create response balance is zero', () {
      expect(
        SalesReturnSync.alreadyApplied(
          {'balance': 0.0, 'total': 136.5},
          [
            {'invoice_id': 'inv_1', 'amount_applied': 136.5},
          ],
        ),
        isTrue,
      );
    });

    test('true when invoices_credited already lists the invoice', () {
      expect(
        SalesReturnSync.alreadyApplied(
          {
            'balance': 136.5,
            'invoices_credited': [
              {'invoice_id': 'inv_1', 'credited_amount': 136.5},
            ],
          },
          [
            {'invoice_id': 'inv_1', 'amount_applied': 136.5},
          ],
        ),
        isTrue,
      );
    });

    test('false when unused credit remains and nothing is credited', () {
      expect(
        SalesReturnSync.alreadyApplied(
          {'balance': 136.5},
          [
            {'invoice_id': 'inv_1', 'amount_applied': 136.5},
          ],
        ),
        isFalse,
      );
    });
  });

  group('SalesReturnSync.isAlreadyAppliedError', () {
    test('matches Zoho already-applied wording', () {
      expect(
        SalesReturnSync.isAlreadyAppliedError(
          Exception('Credit has already been applied to this invoice'),
        ),
        isTrue,
      );
      expect(
        SalesReturnSync.isAlreadyAppliedError(Exception('No unused credits')),
        isTrue,
      );
      expect(
        SalesReturnSync.isAlreadyAppliedError(Exception('Network timeout')),
        isFalse,
      );
    });
  });
}
