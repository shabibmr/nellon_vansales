import '../../domain/models/expense_entry.dart';

class ExpenseLineItemModel extends ExpenseLineItem {
  const ExpenseLineItemModel({
    required super.category,
    required super.amount,
    required super.description,
  });

  factory ExpenseLineItemModel.fromJson(Map<String, dynamic> json) {
    return ExpenseLineItemModel(
      category: json['category'] ?? 'Miscellaneous',
      amount: (json['amount'] ?? 0.0).toDouble(),
      description: json['description'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'amount': amount,
      'description': description,
      'account_id': _getZohoAccountIdForCategory(category),
    };
  }

  static String _getZohoAccountIdForCategory(String category) {
    switch (category) {
      case 'Fuel':
        return 'fuel_expense_ac_id';
      case 'Tolls':
        return 'toll_expense_ac_id';
      case 'Meals':
        return 'meals_expense_ac_id';
      case 'Maintenance':
        return 'maintenance_expense_ac_id';
      default:
        return 'general_expense_ac_id';
    }
  }

  factory ExpenseLineItemModel.fromDomain(ExpenseLineItem domain) {
    return ExpenseLineItemModel(
      category: domain.category,
      amount: domain.amount,
      description: domain.description,
    );
  }
}

class ExpenseEntryModel extends ExpenseEntry {
  const ExpenseEntryModel({
    required super.id,
    required super.date,
    required super.lines,
    super.receiptImagePath,
    super.isPendingSync,
  });

  factory ExpenseEntryModel.fromJson(Map<String, dynamic> json) {
    return ExpenseEntryModel(
      id: json['expense_id'] ?? json['id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      lines: (json['lines'] as List?)
              ?.map((item) => ExpenseLineItemModel.fromJson(item))
              .toList() ??
          [],
      receiptImagePath: json['receiptImagePath'],
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'expense_id': id,
      'date': date.toIso8601String().split('T')[0],
      'receiptImagePath': receiptImagePath,
      'isPendingSync': isPendingSync,
      'amount': amount, // Summed dynamically from lines
      'lines': lines
          .map((item) => ExpenseLineItemModel.fromDomain(item).toJson())
          .toList(),
    };
  }

  factory ExpenseEntryModel.fromDomain(ExpenseEntry expense) {
    return ExpenseEntryModel(
      id: expense.id,
      date: expense.date,
      lines: expense.lines,
      receiptImagePath: expense.receiptImagePath,
      isPendingSync: expense.isPendingSync,
    );
  }
}
