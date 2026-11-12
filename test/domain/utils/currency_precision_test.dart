import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/currency_precision.dart';

void main() {
  group('minorUnitsFor', () {
    test('three-decimal ISO codes', () {
      for (final code in ['KWD', 'kwd', 'BHD', 'OMR', 'JOD', 'IQD', 'LYD', 'TND']) {
        expect(minorUnitsFor(code), 3, reason: code);
      }
    });

    test('zero-decimal ISO codes', () {
      expect(minorUnitsFor('JPY'), 0);
      expect(minorUnitsFor('KRW'), 0);
    });

    test('unknown codes default to 2', () {
      expect(minorUnitsFor('AED'), 2);
      expect(minorUnitsFor('USD'), 2);
      expect(minorUnitsFor(''), 2);
    });
  });
}
