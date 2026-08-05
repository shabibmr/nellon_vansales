import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/ui/features/reports/aggregators/expense_summary_aggregator.dart';

void main() {
  final entry1 = ExpenseEntry(
    id: 'exp_1',
    date: DateTime(2026, 8, 1),
    lines: const [
      ExpenseLineItem(category: 'Fuel', amount: 50.0, description: 'Gasoline'),
      ExpenseLineItem(category: 'Tolls', amount: 10.0, description: 'Highway toll'),
    ],
  );

  final entry2 = ExpenseEntry(
    id: 'exp_2',
    date: DateTime(2026, 8, 2),
    lines: const [
      ExpenseLineItem(category: 'Fuel', amount: 60.0, description: 'Gasoline refill'),
      ExpenseLineItem(category: 'Parking fee', amount: 15.0, description: 'City parking'),
    ],
  );

  final entry3 = ExpenseEntry(
    id: 'exp_3',
    date: DateTime(2026, 8, 5),
    lines: const [
      ExpenseLineItem(category: 'Tolls', amount: 20.0, description: 'Bridge toll'),
    ],
  );

  group('ExpenseSummaryAggregator', () {
    test('aggregates entry count and total amount per category across itemized lines', () {
      final rows = ExpenseSummaryAggregator.aggregate(
        expenses: [entry1, entry2, entry3],
      );

      expect(rows.length, equals(3));

      final fuelRow = rows.firstWhere((r) => r.category == 'Fuel');
      expect(fuelRow.entryCount, equals(2));
      expect(fuelRow.totalAmount, equals(110.0)); // 50 + 60

      final tollRow = rows.firstWhere((r) => r.category == 'Tolls');
      expect(tollRow.entryCount, equals(2));
      expect(tollRow.totalAmount, equals(30.0)); // 10 + 20

      final parkingRow = rows.firstWhere((r) => r.category == 'Parking fee');
      expect(parkingRow.entryCount, equals(1));
      expect(parkingRow.totalAmount, equals(15.0));
    });

    test('filters by date range correctly', () {
      final rows = ExpenseSummaryAggregator.aggregate(
        expenses: [entry1, entry2, entry3],
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );

      expect(rows.length, equals(3));

      final tollRow = rows.firstWhere((r) => r.category == 'Tolls');
      expect(tollRow.entryCount, equals(1)); // entry3 is excluded
      expect(tollRow.totalAmount, equals(10.0));
    });

    test('sorts by amount descending (default)', () {
      final rows = ExpenseSummaryAggregator.aggregate(
        expenses: [entry1, entry2, entry3],
        sortField: ExpenseSummarySortField.amount,
        sortAscending: false,
      );

      expect(rows.first.category, equals('Fuel')); // 110.0 is highest
      expect(rows.last.category, equals('Parking fee')); // 15.0 is lowest
    });

    test('sorts by count ascending', () {
      final rows = ExpenseSummaryAggregator.aggregate(
        expenses: [entry1, entry2, entry3],
        sortField: ExpenseSummarySortField.count,
        sortAscending: true,
      );

      expect(rows.first.category, equals('Parking fee')); // count 1 < 2
    });

    test('sorts by category ascending', () {
      final rows = ExpenseSummaryAggregator.aggregate(
        expenses: [entry1, entry2, entry3],
        sortField: ExpenseSummarySortField.category,
        sortAscending: true,
      );

      expect(rows[0].category, equals('Fuel'));
      expect(rows[1].category, equals('Parking fee'));
      expect(rows[2].category, equals('Tolls'));
    });

    test('handles empty expense list', () {
      final rows = ExpenseSummaryAggregator.aggregate(expenses: []);
      expect(rows, isEmpty);
    });
  });
}
