import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/amount_in_words.dart';

void main() {
  group('amountInWords', () {
    test('zero', () {
      expect(
        amountInWords(0, currencyName: 'AED'),
        'AED Zero only',
      );
    });

    test('fraction only', () {
      expect(
        amountInWords(0.5, currencyName: 'AED'),
        'AED Zero And fifty fils.',
      );
    });

    test('simple whole', () {
      expect(
        amountInWords(15, currencyName: 'AED'),
        'AED Fifteen only',
      );
    });

    test('whole dirhams omit 00/100', () {
      expect(
        amountInWords(248, currencyName: 'AED'),
        'AED Two Hundred Forty-Eight only',
      );
      expect(
        amountInWords(248.00, currencyName: 'AED'),
        'AED Two Hundred Forty-Eight only',
      );
    });

    test('56 fils is written in words', () {
      expect(
        amountInWords(11.56, currencyName: 'AED'),
        'AED Eleven And fifty six fils.',
      );
    });

    test('thousands with fils in words', () {
      expect(
        amountInWords(1234.56, currencyName: 'AED'),
        'AED One Thousand Two Hundred Thirty-Four And fifty six fils.',
      );
    });

    test('without currency name', () {
      expect(amountInWords(2), 'Two only');
    });
  });

  group('currencyUnitName', () {
    test('maps common codes', () {
      expect(currencyUnitName('AED'), 'AED');
      expect(currencyUnitName('INR'), 'Rupees');
      expect(currencyUnitName('USD'), 'Dollars');
    });
  });
}
