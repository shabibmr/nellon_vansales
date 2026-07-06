import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/ui/features/stock_transfer/bloc/stock_transfer_bloc.dart';

void main() {
  const item = Item(
    id: 'item_1',
    name: 'Item One',
    sku: 'SKU1',
    rate: 10.0,
    stock: 10,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0.0,
  );

  group('StockTransferRow column math', () {
    test('subtotal (Col 3) is current stock plus today\'s invoiced quantity', () {
      const row = StockTransferRow(item: item, currentStock: 20, invoiceQty: 8);
      expect(row.subtotal, equals(28));
    });

    test('grandTotal (Col 5) adds the editable extra quantity on top of subtotal', () {
      const row = StockTransferRow(
        item: item,
        currentStock: 20,
        invoiceQty: 8,
        extraQty: 5,
      );
      expect(row.subtotal, equals(28));
      expect(row.grandTotal, equals(33));
    });

    test('a brand-new row (no current stock, no invoices) still totals correctly', () {
      const row = StockTransferRow(item: item, currentStock: 0, extraQty: 12);
      expect(row.subtotal, equals(0));
      expect(row.grandTotal, equals(12));
    });
  });

  group('StockTransferState.transferQtyFor', () {
    test(
      'load direction transfers invoiceQty + extraQty, excluding current stock '
      'already on the van',
      () {
        const row = StockTransferRow(
          item: item,
          currentStock: 20,
          invoiceQty: 8,
          extraQty: 5,
        );
        const state = StockTransferState(
          direction: StockTransferDirection.load,
          rows: [row],
        );
        expect(state.transferQtyFor(row), equals(13));
        expect(state.totalTransferQty, equals(13));
      },
    );

    test('unload direction transfers only the editable extraQty (the balance to return)', () {
      const row = StockTransferRow(
        item: item,
        currentStock: 20,
        invoiceQty: 8, // irrelevant for unload
        extraQty: 15,
      );
      const state = StockTransferState(
        direction: StockTransferDirection.unload,
        rows: [row],
      );
      expect(state.transferQtyFor(row), equals(15));
      expect(state.totalTransferQty, equals(15));
    });

    test('totalTransferQty sums across multiple rows', () {
      const item2 = Item(
        id: 'item_2',
        name: 'Item Two',
        sku: 'SKU2',
        rate: 5.0,
        stock: 4,
        description: '',
        taxName: 'No Tax',
        taxPercentage: 0.0,
      );
      const rows = [
        StockTransferRow(item: item, currentStock: 20, invoiceQty: 8, extraQty: 5),
        StockTransferRow(item: item2, currentStock: 4, invoiceQty: 2, extraQty: 0),
      ];
      const state = StockTransferState(
        direction: StockTransferDirection.load,
        rows: rows,
      );
      // (8+5) + (2+0) = 15
      expect(state.totalTransferQty, equals(15));
    });

    test('a row with zero transfer quantity is excluded when building submit lines', () {
      const zeroRow = StockTransferRow(item: item, currentStock: 5);
      const state = StockTransferState(
        direction: StockTransferDirection.load,
        rows: [zeroRow],
      );
      expect(state.transferQtyFor(zeroRow), equals(0));
      final linesToTransfer =
          state.rows.where((r) => state.transferQtyFor(r) > 0).toList();
      expect(linesToTransfer, isEmpty);
    });
  });
}
