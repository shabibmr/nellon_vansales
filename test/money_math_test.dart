import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/money_math.dart';

void main() {
  group('roundTotal', () {
    tearDown(() {
      MoneyScale.use(2);
      MoneyScale.useTotalStep(0);
    });

    test('step 0 only rounds to the money scale', () {
      MoneyScale.useTotalStep(0);
      expect(roundTotal(10.404), 10.40);
    });

    test('step 0.5 rounds to the nearest half', () {
      MoneyScale.useTotalStep(0.5);
      expect(roundTotal(10.00), 10.00);
      expect(roundTotal(10.24), 10.00);
      expect(roundTotal(10.25), 10.50);
      expect(roundTotal(10.40), 10.50);
      expect(roundTotal(10.74), 10.50);
      expect(roundTotal(10.75), 11.00);
    });

    test('step 1 rounds to whole units', () {
      MoneyScale.useTotalStep(1);
      expect(roundTotal(10.49), 10.0);
      expect(roundTotal(10.50), 11.0);
    });

    test('step 0.5 still applies at 3 decimals', () {
      MoneyScale.use(3);
      MoneyScale.useTotalStep(0.5);
      expect(roundTotal(1.10), 1.0);
    });

    test('negative step is treated as 0', () {
      MoneyScale.useTotalStep(-1);
      expect(MoneyScale.totalStep, 0);
    });
  });

  group('detectTotalRoundingStep', () {
    List<double> repeat(List<double> v) => [for (var i = 0; i < 4; i++) ...v];

    test('all multiples of 0.5 detect 0.5', () {
      expect(detectTotalRoundingStep(repeat([10.5, 21.0, 3.5])), 0.5);
    });

    test('all whole numbers detect 1', () {
      expect(detectTotalRoundingStep(repeat([10, 21, 3, 7])), 1.0);
    });

    test('mixed fils detect 0', () {
      expect(detectTotalRoundingStep(repeat([10.5, 21.0, 3.42])), 0);
    });

    test('3-decimal KWD totals detect 0', () {
      expect(detectTotalRoundingStep(repeat([3.750, 1.235, 12.125])), 0);
    });

    test('zero totals are ignored', () {
      expect(
        detectTotalRoundingStep([...repeat([10.5, 21.0, 3.5]), 0, 0.0]),
        0.5,
      );
    });

    test('fewer than 10 samples returns null', () {
      expect(detectTotalRoundingStep([10.5, 21.0, 0, 0, 0]), isNull);
    });
  });

  group('roundMoney scale', () {
    tearDown(() => MoneyScale.use(2));

    test('3 decimal places rounds 1.2254 to 1.225', () {
      MoneyScale.use(3);
      expect(roundMoney(1.2254), 1.225);
      MoneyScale.use(2);
    });

    test('2 decimal places rounds 1.225 half away from zero', () {
      MoneyScale.use(2);
      expect(roundMoney(1.225), 1.23);
    });

  });
}
