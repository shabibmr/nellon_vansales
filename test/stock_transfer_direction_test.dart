import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/utils/stock_transfer_direction.dart';

void main() {
  const van = 'van_1';

  test('van in to (and not from) is Issue to Van', () {
    expect(
      inferStockTransferDirection(
        fromLocationId: 'wh',
        toLocationId: van,
        vanLocationId: van,
      ),
      StockTransferDirection.load,
    );
  });

  test('van in from (and not to) is Stock Unloading', () {
    expect(
      inferStockTransferDirection(
        fromLocationId: van,
        toLocationId: 'wh',
        vanLocationId: van,
      ),
      StockTransferDirection.unload,
    );
  });

  test('missing van keeps stored direction, defaulting to load', () {
    expect(
      inferStockTransferDirection(
        fromLocationId: van,
        toLocationId: 'wh',
      ),
      StockTransferDirection.load,
    );
    expect(
      inferStockTransferDirection(
        fromLocationId: van,
        toLocationId: 'wh',
        stored: StockTransferDirection.unload,
      ),
      StockTransferDirection.unload,
    );
  });

  test('van on both ends keeps stored / default', () {
    expect(
      inferStockTransferDirection(
        fromLocationId: van,
        toLocationId: van,
        vanLocationId: van,
        stored: StockTransferDirection.unload,
      ),
      StockTransferDirection.unload,
    );
  });
}
