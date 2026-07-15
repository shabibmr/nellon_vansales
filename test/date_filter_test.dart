import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/utils/date_filter.dart';

void main() {
  group('todayDate', () {
    test('returns calendar day of now when no argument is given', () {
      final now = DateTime.now();
      final result = todayDate();
      expect(result, DateTime(now.year, now.month, now.day));
      expect(result.hour, 0);
      expect(result.minute, 0);
    });

    test('strips time-of-day from a provided date', () {
      final result = todayDate(DateTime(2026, 7, 15, 23, 59, 59));
      expect(result, DateTime(2026, 7, 15));
    });
  });

  group('filterByDateRange', () {
    final items = [
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 15),
      DateTime(2026, 1, 31),
    ];

    test('returns all items when both bounds are null', () {
      final result = filterByDateRange(items, (d) => d);
      expect(result, equals(items));
    });

    test('excludes items before startDate', () {
      final result = filterByDateRange(
        items,
        (d) => d,
        startDate: DateTime(2026, 1, 10),
      );
      expect(result, equals([DateTime(2026, 1, 15), DateTime(2026, 1, 31)]));
    });

    test('excludes items after endDate', () {
      final result = filterByDateRange(
        items,
        (d) => d,
        endDate: DateTime(2026, 1, 20),
      );
      expect(result, equals([DateTime(2026, 1, 1), DateTime(2026, 1, 15)]));
    });

    test('is inclusive of the boundary dates', () {
      final result = filterByDateRange(
        items,
        (d) => d,
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );
      expect(result, equals(items));
    });

    test('ignores time-of-day when comparing to a boundary', () {
      final withTime = [DateTime(2026, 1, 15, 23, 59)];
      final result = filterByDateRange(
        withTime,
        (d) => d,
        startDate: DateTime(2026, 1, 15),
        endDate: DateTime(2026, 1, 15),
      );
      expect(result, equals(withTime));
    });
  });
}
