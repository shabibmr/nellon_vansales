import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/amount_in_words.dart';

void main() {
  group('amountInWords', () {
    test('zero', () {
      expect(
        amountInWords(0, currencyName: 'Dirhams'),
        'Dirhams Zero and 00/100 only',
      );
    });

    test('fraction only', () {
      expect(
        amountInWords(0.5, currencyName: 'Dirhams'),
        'Dirhams Zero and 50/100 only',
      );
    });

    test('simple whole', () {
      expect(
        amountInWords(15, currencyName: 'Dirhams'),
        'Dirhams Fifteen and 00/100 only',
      );
    });

    test('thousands with cents', () {
      expect(
        amountInWords(1234.56, currencyName: 'Dirhams'),
        'Dirhams One Thousand Two Hundred Thirty-Four and 56/100 only',
      );
    });

    test('without currency name', () {
      expect(amountInWords(2), 'Two and 00/100 only');
    });
  });

  group('currencyUnitName', () {
    test('maps common codes', () {
      expect(currencyUnitName('AED'), 'Dirhams');
      expect(currencyUnitName('INR'), 'Rupees');
      expect(currencyUnitName('USD'), 'Dollars');
    });
  });
}
