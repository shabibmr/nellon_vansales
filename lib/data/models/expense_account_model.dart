import '../../domain/models/expense_account.dart';

/// Data transfer object representing an [ExpenseAccount] ledger mapping.
///
/// Directs the translation between Zoho Books account objects and the local system accounts representation.
class ExpenseAccountModel extends ExpenseAccount {
  /// Creates a new [ExpenseAccountModel] instance.
  const ExpenseAccountModel({
    required super.id,
    required super.name,
    required super.accountCode,
    required super.category,
  });

  /// Factory constructor to parse local/remote JSON maps into an [ExpenseAccountModel].
  ///
  /// Mappes Zoho ledger fields (`account_id`, `account_name`, `account_code`) with fallback defaults.
  factory ExpenseAccountModel.fromJson(Map<String, dynamic> json) {
    return ExpenseAccountModel(
      id: json['account_id'] ?? json['id'] ?? '',
      name: json['account_name'] ?? json['name'] ?? '',
      accountCode: json['account_code'] ?? json['accountCode'] ?? '',
      category: json['category'] ?? json['account_name'] ?? '',
    );
  }

  /// Converts this [ExpenseAccountModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': id,
      'name': name,
      'account_name': name,
      'account_code': accountCode,
      'category': category,
    };
  }

  /// Translates a base domain [ExpenseAccount] entity into a serializable [ExpenseAccountModel].
  factory ExpenseAccountModel.fromDomain(ExpenseAccount a) {
    return ExpenseAccountModel(
      id: a.id,
      name: a.name,
      accountCode: a.accountCode,
      category: a.category,
    );
  }
}

