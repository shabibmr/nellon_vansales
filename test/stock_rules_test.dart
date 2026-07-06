import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/stock_rules.dart';

void main() {
  group('deductStock', () {
    test('returns the remaining stock when quantity is available', () {
      final remaining = deductStock(
        itemId: 'item_1',
        itemName: 'Widget',
        available: 10,
        requested: 4,
      );
      expect(remaining, equals(6));
    });

    test('allows deducting exactly all remaining stock', () {
      final remaining = deductStock(
        itemId: 'item_1',
        itemName: 'Widget',
        available: 5,
        requested: 5,
      );
      expect(remaining, equals(0));
    });

    test(
      'throws InsufficientStockException instead of silently flooring to zero',
      () {
        expect(
          () => deductStock(
            itemId: 'item_1',
            itemName: 'Widget',
            available: 3,
            requested: 5,
          ),
          throwsA(
            isA<InsufficientStockException>()
                .having((e) => e.itemId, 'itemId', 'item_1')
                .having((e) => e.available, 'available', 3)
                .having((e) => e.requested, 'requested', 5),
          ),
        );
      },
    );

    test('exception message names the item and the shortfall', () {
      const exception = InsufficientStockException(
        itemId: 'item_1',
        itemName: 'Widget',
        available: 3,
        requested: 5,
      );
      expect(exception.toString(), contains('Widget'));
      expect(exception.toString(), contains('3'));
      expect(exception.toString(), contains('5'));
    });
  });
}
