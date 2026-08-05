import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/expense_entry_model.dart';

void main() {
  group('ExpenseEntryModel.fromZohoJson', () {
    test('maps line_items account_name into lines category', () {
      final expense = ExpenseEntryModel.fromZohoJson({
        'expense_id': 'exp_1',
        'date': '2026-03-01',
        'line_items': [
          {
            'account_name': 'Fuel',
            'amount': 42.5,
            'description': 'Diesel fill',
          },
        ],
      });

      expect(expense.id, 'exp_1');
      expect(expense.lines, hasLength(1));
      expect(expense.lines.first.category, 'Fuel');
      expect(expense.lines.first.amount, 42.5);
      expect(expense.lines.first.description, 'Diesel fill');
      expect(expense.amount, 42.5);
    });

    test('keeps local lines shape when line_items absent', () {
      final expense = ExpenseEntryModel.fromZohoJson({
        'id': 'exp_local',
        'date': '2026-03-02',
        'lines': [
          {
            'category': 'Tolls',
            'amount': 10,
            'description': 'Highway',
          },
        ],
      });

      expect(expense.lines.single.category, 'Tolls');
      expect(expense.amount, 10);
    });

    test('header JSON maps listedTotal and category without line items', () {
      final expense = ExpenseEntryModel.fromZohoJson({
        'expense_id': 'exp_hdr',
        'date': '2026-03-03',
        'total': 99.5,
        'account_name': 'Fuel',
        'description': 'Pump stop',
      });

      expect(expense.lines, isEmpty);
      expect(expense.listedTotal, 99.5);
      expect(expense.amount, 99.5);
      expect(expense.displayCategory, 'Fuel');
      expect(expense.displayDescription, 'Pump stop');
    });

    test('line items win over listedTotal for amount', () {
      final expense = ExpenseEntryModel.fromZohoJson({
        'expense_id': 'exp_detail',
        'date': '2026-03-04',
        'total': 9999,
        'line_items': [
          {
            'account_name': 'Tolls',
            'amount': 15,
            'description': 'Bridge',
          },
        ],
      });

      expect(expense.amount, 15);
      expect(expense.displayCategory, 'Tolls');
    });
  });
}
