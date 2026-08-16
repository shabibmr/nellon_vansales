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
      category: (json['category'] as String?) ?? 'Parking fee',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      description: (json['description'] as String?) ?? '',
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
      case 'Maintenance':
        return 'maintenance_expense_ac_id';
      case 'Parking fee':
        return 'parking_expense_ac_id';
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
    super.zohoExpenseId,
    super.locationId,
    super.listedTotal,
    super.listedCategory,
    super.listedDescription,
  });

  /// Factory constructor to parse local database JSON maps into an [ExpenseEntryModel].
  factory ExpenseEntryModel.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'] ?? json['amount'] ?? json['listedTotal'];
    double? listedTotal;
    if (rawTotal is num) {
      listedTotal = rawTotal.toDouble();
    } else if (rawTotal != null) {
      listedTotal = double.tryParse(rawTotal.toString());
    }

    return ExpenseEntryModel(
      id: ((json['expense_id'] ?? json['id']) as String?) ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      lines:
          (json['lines'] as List?)
              ?.map((item) => ExpenseLineItemModel.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      receiptImagePath: json['receiptImagePath'] as String?,
      isPendingSync: (json['isPendingSync'] as bool?) ?? false,
      zohoExpenseId: (json['zoho_expense_id'] ?? json['zohoExpenseId'])
          ?.toString(),
      locationId: json['location_id'] as String?,
      listedTotal: listedTotal,
      listedCategory: (json['listedCategory'] ??
              json['account_name'] ??
              '')
          .toString(),
      listedDescription:
          (json['listedDescription'] ?? json['description'] ?? '').toString(),
    );
  }

  /// Parses a Zoho Books expense envelope (`line_items` / `account_name`).
  ///
  /// Local Hive records already use [fromJson] with a `lines` array. Zoho detail
  /// and list payloads use `line_items` with `account_name` instead of `category`.
  /// List headers often omit `line_items` but still carry `total` / `account_name`.
  factory ExpenseEntryModel.fromZohoJson(Map<String, dynamic> json) {
    return ExpenseEntryModel.fromJson(normalizeZohoExpenseJson(json));
  }

  /// Maps Zoho `line_items` → local `lines` shape expected by [fromJson].
  ///
  /// If [json] already has `lines` and no `line_items`, it is returned as-is.
  static Map<String, dynamic> normalizeZohoExpenseJson(
    Map<String, dynamic> json,
  ) {
    final lineItems = (json['line_items'] as List?) ?? const [];
    if (lineItems.isEmpty && json['lines'] != null) {
      return json;
    }
    return {
      ...json,
      'lines': lineItems
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (l) => <String, dynamic>{
              'category': l['account_name'] ?? l['category'] ?? 'Miscellaneous',
              'amount': l['amount'] ?? 0.0,
              'description': l['description'] ?? '',
            },
          )
          .toList(),
    };
  }

  /// Converts this [ExpenseEntryModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'expense_id': id,
      'date': date.toIso8601String().split('T')[0],
      'receiptImagePath': receiptImagePath,
      'isPendingSync': isPendingSync,
      'zoho_expense_id': zohoExpenseId,
      'location_id': locationId,
      'amount': amount,
      if (listedTotal != null) 'total': listedTotal,
      if (listedCategory.isNotEmpty) 'listedCategory': listedCategory,
      if (listedCategory.isNotEmpty) 'account_name': listedCategory,
      if (listedDescription.isNotEmpty) 'listedDescription': listedDescription,
      if (listedDescription.isNotEmpty) 'description': listedDescription,
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
      zohoExpenseId: expense.zohoExpenseId,
      locationId: expense.locationId,
      listedTotal: expense.listedTotal,
      listedCategory: expense.listedCategory,
      listedDescription: expense.listedDescription,
    );
  }
}
