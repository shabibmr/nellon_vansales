import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/phone_normalizer.dart';

void main() {
  group('normalizePhone', () {
    test('leaves an already-E.164 number unchanged', () {
      expect(normalizePhone('+971542891246'), '+971542891246');
    });

    test('converts 00 international prefix to +', () {
      expect(normalizePhone('00971542891246'), '+971542891246');
    });

    test('converts local 05 mobile format to +971', () {
      expect(normalizePhone('0542891246'), '+971542891246');
    });

    test('adds + to a bare country-code number', () {
      expect(normalizePhone('971542891246'), '+971542891246');
    });

    test('converts bare 9-digit mobile number to +971', () {
      expect(normalizePhone('542891246'), '+971542891246');
    });

    test('strips spaces, dashes, and parens before normalizing', () {
      expect(normalizePhone('054 289-1246'), '+971542891246');
      expect(normalizePhone('(971) 542-891-246'), '+971542891246');
      expect(normalizePhone('+971 54 289 1246'), '+971542891246');
    });

    test('returns empty string for empty input', () {
      expect(normalizePhone(''), '');
    });

    test('leaves an unrecognized shape unchanged and fails validation', () {
      final normalized = normalizePhone('12345');
      expect(normalized, '12345');
      expect(isValidE164(normalized), isFalse);
    });
  });

  group('isValidE164', () {
    test('accepts a normalized UAE mobile number', () {
      expect(isValidE164(normalizePhone('0542891246')), isTrue);
    });

    test('rejects a number without a leading +', () {
      expect(isValidE164('971542891246'), isFalse);
    });
  });
}
