import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/money_math.dart';

void main() {
  group('roundToNearestHalf', () {
    test('stays on whole and half fils', () {
      expect(roundToNearestHalf(10.00), 10.00);
      expect(roundToNearestHalf(10.50), 10.50);
    });

    test('rounds down toward 0.00 or 0.50', () {
      expect(roundToNearestHalf(10.10), 10.00);
      expect(roundToNearestHalf(10.24), 10.00);
      expect(roundToNearestHalf(10.60), 10.50);
      expect(roundToNearestHalf(10.74), 10.50);
    });

    test('rounds up toward 0.00 or 0.50', () {
      expect(roundToNearestHalf(10.25), 10.50);
      expect(roundToNearestHalf(10.40), 10.50);
      expect(roundToNearestHalf(10.75), 11.00);
      expect(roundToNearestHalf(10.90), 11.00);
    });
  });
}
