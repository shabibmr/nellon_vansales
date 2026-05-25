import '../../domain/models/expense_entry.dart';

/// Data transfer object representing a specific [ExpenseLineItem].
///
/// Maps categories (Fuel, Tolls, etc.) to hardcoded backend ledger accounts in Zoho.
class ExpenseLineItemModel extends ExpenseLineItem {
  /// Creates a new [ExpenseLineItemModel] instance.
  const ExpenseLineItemModel({
    required super.category,
    required super.amount,
    required super.description,
  });

  /// Factory constructor to parse local database JSON maps into an [ExpenseLineItemModel].
  factory ExpenseLineItemModel.fromJson(Map<String, dynamic> json) {
    return ExpenseLineItemModel(
      category: json['category'] ?? 'Miscellaneous',
      amount: (json['amount'] ?? 0.0).toDouble(),
      description: json['description'] ?? '',
    );
  }

  /// Converts this [ExpenseLineItemModel] into a serialization compatible JSON map, injecting Zoho Account ID mappings.
  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'amount': amount,
      'description': description,
      'account_id': _getZohoAccountIdForCategory(category),
    };
  }

  /// Maps local UI expense category labels directly to Zoho Book expense ledger account IDs.
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

  /// Translates a base domain [ExpenseLineItem] entity into its [ExpenseLineItemModel] DTO representation.
  factory ExpenseLineItemModel.fromDomain(ExpenseLineItem domain) {
    return ExpenseLineItemModel(
      category: domain.category,
      amount: domain.amount,
      description: domain.description,
    );
  }
}

/// Data transfer object representing the overall [ExpenseEntry] voucher log.
///
/// Bundles multi-line logs and formats receipt attachment variables for local database and background uploading.
class ExpenseEntryModel extends ExpenseEntry {
  /// Creates a new [ExpenseEntryModel] instance.
  const ExpenseEntryModel({
    required super.id,
    required super.date,
    required super.lines,
    super.receiptImagePath,
    super.isPendingSync,
  });

  /// Factory constructor to parse local database JSON maps into an [ExpenseEntryModel].
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

  /// Converts this [ExpenseEntryModel] instance into a serializable JSON map.
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

  /// Translates a base domain [ExpenseEntry] entity into its [ExpenseEntryModel] representation.
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

