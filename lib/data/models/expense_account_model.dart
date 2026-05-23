import '../../domain/models/expense_account.dart';

class ExpenseAccountModel extends ExpenseAccount {
  const ExpenseAccountModel({
    required super.id,
    required super.name,
    required super.accountCode,
    required super.category,
  });

  factory ExpenseAccountModel.fromJson(Map<String, dynamic> json) {
    return ExpenseAccountModel(
      id: json['account_id'] ?? json['id'] ?? '',
      name: json['account_name'] ?? json['name'] ?? '',
      accountCode: json['account_code'] ?? json['accountCode'] ?? '',
      category: json['category'] ?? json['account_name'] ?? '',
    );
  }

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

  factory ExpenseAccountModel.fromDomain(ExpenseAccount a) {
    return ExpenseAccountModel(
      id: a.id,
      name: a.name,
      accountCode: a.accountCode,
      category: a.category,
    );
  }
}
