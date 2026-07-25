import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/item_model.dart';
import 'package:van_sales/data/models/sales_invoice_model.dart';
import 'package:van_sales/data/models/sales_return_model.dart';
import 'package:van_sales/data/models/unit_conversion_model.dart';
import 'package:van_sales/data/services/zoho_payload_mapper.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/models/unit_conversion.dart';
import 'package:van_sales/ui/core/cubit/line_editor_cubit.dart';
import 'package:van_sales/ui/core/utils/quantity_format.dart';

/// Mirrors the live-org shape: base unit kg @ 4.875, "25 Kg Bag" ×25.
const _bagConversion = UnitConversion(
  unitConversionId: '3331482000000248413',
  targetUnitId: 'u_25kg',
  targetUnit: '25 Kg Bag',
  conversionRate: 25.0,
  quantityDecimalPlaces: 0,
);

const _gramConversion = UnitConversion(
  unitConversionId: 'uc_g',
  targetUnitId: 'u_g',
  targetUnit: 'g',
  conversionRate: 0.001,
  quantityDecimalPlaces: 0,
);

Item _rice({double stock = 500}) => Item(
      id: 'item_rice',
      name: '1121 GOLDEN SELLA RICE',
      sku: 'RICE-1121',
      rate: 4.875,
      stock: stock,
      description: '',
      taxName: 'VAT 5%',
      taxPercentage: 5.0,
      uom: 'kg',
      unitConversions: const [_bagConversion, _gramConversion],
    );

void main() {
  group('UnitConversionModel', () {
    test('round-trips Zoho JSON', () {
      final json = {
        'unit_conversion_id': 'uc1',
        'target_unit_id': 'tu1',
        'target_unit': '25 Kg Bag',
        'conversion_rate': 25.0,
        'quantity_decimal_place': 2,
      };
      final model = UnitConversionModel.fromJson(json);
      expect(model.unitConversionId, 'uc1');
      expect(model.targetUnit, '25 Kg Bag');
      expect(model.conversionRate, 25.0);
      expect(model.quantityDecimalPlaces, 2);
      expect(model.toJson(), json);
    });
  });

  group('ItemModel unit_conversions', () {
    test('parses and round-trips unit_conversions', () {
      final model = ItemModel.fromJson({
        'item_id': 'i1',
        'name': 'Rice',
        'rate': 4.875,
        'unit': 'kg',
        'unit_conversions': [
          {
            'unit_conversion_id': 'uc1',
            'target_unit_id': 'tu1',
            'target_unit': '25 Kg Bag',
            'conversion_rate': 25,
            'quantity_decimal_place': 0,
          },
        ],
      });
      expect(model.unitConversions, hasLength(1));
      final reparsed = ItemModel.fromJson(model.toJson());
      expect(reparsed.unitConversions.single.targetUnit, '25 Kg Bag');
      expect(reparsed.unitConversions.single.conversionRate, 25.0);
    });

    test('legacy cached items without the key parse to empty list', () {
      final model = ItemModel.fromJson({'item_id': 'i1', 'name': 'Old'});
      expect(model.unitConversions, isEmpty);
    });
  });

  group('Item price/conversion helpers', () {
    test('rateFor scales the base rate by conversion rate', () {
      final item = _rice();
      expect(item.rateFor('kg'), 4.875);
      expect(item.rateFor('25 Kg Bag'), 4.875 * 25);
      expect(item.rateFor('g'), closeTo(0.004875, 1e-9));
    });

    test('conversionRateFor falls back to 1.0 for base/unknown units', () {
      final item = _rice();
      expect(item.conversionRateFor('kg'), 1.0);
      expect(item.conversionRateFor('nonsense'), 1.0);
      expect(item.conversionRateFor('25 Kg Bag'), 25.0);
    });
  });

  group('InvoiceLineItem multi-UOM', () {
    test('quantityInBase converts selected-unit qty to base units', () {
      final line = InvoiceLineItem(
        item: _rice(),
        quantity: 2,
        rate: 121.875,
        taxPercentage: 5,
        uom: '25 Kg Bag',
        unitConversionId: _bagConversion.unitConversionId,
      );
      expect(line.quantityInBase, 50.0);
      expect(line.subTotal, 243.75);
    });

    test('base-unit line keeps quantity as-is', () {
      final line = InvoiceLineItem(
        item: _rice(),
        quantity: 3.5,
        rate: 4.875,
        taxPercentage: 5,
        uom: 'kg',
      );
      expect(line.quantityInBase, 3.5);
    });
  });

  group('Line DTO payloads', () {
    test('invoice line toJson emits unit + unit_conversion_id when set', () {
      final model = InvoiceLineItemModel.fromDomain(
        InvoiceLineItem(
          item: _rice(),
          quantity: 2,
          rate: 121.875,
          taxPercentage: 5,
          uom: '25 Kg Bag',
          unitConversionId: 'uc_bag',
        ),
      );
      final json = model.toJson();
      expect(json['unit'], '25 Kg Bag');
      expect(json['unit_conversion_id'], 'uc_bag');
      expect(json['quantity'], 2.0);
      expect(json['rate'], 121.875);
    });

    test('invoice line toJson omits unit_conversion_id for base unit', () {
      final model = InvoiceLineItemModel.fromDomain(
        InvoiceLineItem(
          item: _rice(),
          quantity: 3,
          rate: 4.875,
          taxPercentage: 5,
          uom: 'kg',
        ),
      );
      expect(model.toJson().containsKey('unit_conversion_id'), isFalse);
    });

    test('mapper keeps unit_conversion_id on invoice/salesorder lines', () {
      final raw = {
        'customer_id': 'c1',
        'line_items': [
          {
            'item_id': 'i1',
            'quantity': 2.0,
            'rate': 121.875,
            'tax_percentage': 5.0,
            'discount': 0.0,
            'unit': '25 Kg Bag',
            'unit_conversion_id': 'uc_bag',
            'item': {'id': 'i1'},
          },
        ],
      };
      final inv = ZohoPayloadMapper.zohoInvoicePayload(raw);
      expect(inv['line_items'][0]['unit_conversion_id'], 'uc_bag');
      expect(inv['line_items'][0].containsKey('item'), isFalse);
      final so = ZohoPayloadMapper.zohoSalesOrderPayload(raw);
      expect(so['line_items'][0]['unit_conversion_id'], 'uc_bag');
    });

    test('mapper keeps unit + unit_conversion_id on credit-note lines', () {
      final out = ZohoPayloadMapper.zohoCreditNotePayload({
        'customer_id': 'c1',
        'line_items': [
          {
            'item_id': 'i1',
            'quantity': 1.0,
            'rate': 121.875,
            'invoice_id': 'inv1',
            'unit': '25 Kg Bag',
            'unit_conversion_id': 'uc_bag',
          },
        ],
      });
      expect(out['line_items'][0]['unit'], '25 Kg Bag');
      expect(out['line_items'][0]['unit_conversion_id'], 'uc_bag');
    });
  });

  group('SalesReturnLineItem converted rate and quantities', () {
    InvoiceLineItem soldInBags() => InvoiceLineItem(
          item: _rice(),
          quantity: 2, // 2 × 25 Kg Bag = 50 kg
          rate: 121.875, // per bag
          taxPercentage: 0,
          discount: 10.0,
          uom: '25 Kg Bag',
          unitConversionId: _bagConversion.unitConversionId,
        );

    test('return in the sold unit uses the invoiced rate', () {
      final line = SalesReturnLineItem(
        invoiceLineItem: soldInBags(),
        returnedQuantity: 1,
      );
      expect(line.displayUom, '25 Kg Bag');
      expect(line.rate, 121.875);
      expect(line.subTotal, 121.88); // money-rounded line total
      expect(line.returnedQuantityInBase, 25.0);
    });

    test('return in kg derives the base rate from the invoiced bag rate', () {
      final line = SalesReturnLineItem(
        invoiceLineItem: soldInBags(),
        returnedQuantity: 10,
        uom: 'kg',
      );
      // 121.875 / 25 = 4.875 per kg
      expect(line.rate, 4.875);
      expect(line.subTotal, 48.75);
      expect(line.returnedQuantityInBase, 10.0);
    });

    test('discount prorates in base units across units', () {
      // Sold 50 kg with 10.00 discount → 0.2/kg. Returning 10 kg → 2.00.
      final line = SalesReturnLineItem(
        invoiceLineItem: soldInBags(),
        returnedQuantity: 10,
        uom: 'kg',
      );
      expect(line.discountAmount, 2.0);
    });

    test('DTO round-trips the return unit override', () {
      final model = SalesReturnLineItemModel.fromDomain(
        SalesReturnLineItem(
          invoiceLineItem: soldInBags(),
          returnedQuantity: 10,
          invoiceId: 'inv1',
          uom: 'kg',
        ),
      );
      final json = model.toJson();
      expect(json['unit'], 'kg');
      expect(json['quantity'], 10.0);
      expect(json['rate'], 4.875);
      final reparsed = SalesReturnLineItemModel.fromJson(json);
      expect(reparsed.uom, 'kg');
      expect(reparsed.returnedQuantity, 10.0);
    });
  });

  group('StockTransferLine base-unit storage', () {
    test('stores base quantity with entered-unit metadata', () {
      final line = StockTransferLine(
        item: _rice(),
        quantity: 50, // base kg
        uom: '25 Kg Bag',
        conversionRate: 25,
      );
      expect(line.enteredQuantity, 2.0);
      expect(line.quantity, 50.0);
    });
  });

  group('LineEditorCubit.setUnit', () {
    test('recomputes rate as base rate × conversion rate', () {
      final cubit = LineEditorCubit(
        initialQuantity: 1,
        initialRate: 4.875,
        initialDiscount: 0,
        taxPercentage: 5,
      );
      cubit.setUnit(baseRate: 4.875, conversionRate: 25);
      expect(cubit.state.rate, 121.875);
      // Rate stays user-editable afterwards.
      cubit.setRate(120.0);
      expect(cubit.state.rate, 120.0);
      cubit.close();
    });

    test('decimal quantities feed totals math', () {
      final cubit = LineEditorCubit(
        initialQuantity: 1,
        initialRate: 4.875,
        initialDiscount: 0,
        taxPercentage: 0,
      );
      cubit.setQuantity(2.5);
      expect(cubit.state.subtotal, closeTo(12.1875, 1e-9));
      cubit.close();
    });
  });

  group('formatQuantity', () {
    test('trims trailing zeros and keeps decimals', () {
      expect(formatQuantity(3.0), '3');
      expect(formatQuantity(2.5), '2.5');
      expect(formatQuantity(0.25), '0.25');
      expect(formatQuantity(2.5001, maxDecimals: 2), '2.5');
    });
  });

  group('Order → invoice multi-UOM mapping', () {
    test('preserves unitConversionId when mapping order lines to invoice lines',
        () {
      // Mirrors StartInvoiceFromOrder / _convertSingleOrder mapping.
      final orderLine = OrderLineItem(
        item: _rice(),
        quantity: 2,
        rate: 121.875,
        taxPercentage: 5,
        uom: '25 Kg Bag',
        unitConversionId: _bagConversion.unitConversionId,
      );
      final invoiceLine = InvoiceLineItem(
        item: orderLine.item,
        quantity: orderLine.quantity,
        rate: orderLine.rate,
        taxPercentage: orderLine.taxPercentage,
        discount: orderLine.discount,
        uom: orderLine.displayUom,
        unitConversionId: orderLine.unitConversionId,
      );
      expect(invoiceLine.unitConversionId, _bagConversion.unitConversionId);
      expect(invoiceLine.displayUom, '25 Kg Bag');
      expect(invoiceLine.quantityInBase, 50.0);
    });
  });
}
