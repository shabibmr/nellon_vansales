import 'package:equatable/equatable.dart';

/// A Zoho Books expense ledger. The van app maps each UI expense category
/// (Fuel / Tolls / Meals / Maintenance / Miscellaneous) to one of these.
class ExpenseAccount extends Equatable {
  final String id; // Zoho account_id
  final String name;
  final String accountCode;
  final String category; // UI-facing category label

  const ExpenseAccount({
    required this.id,
    required this.name,
    required this.accountCode,
    required this.category,
  });

  ExpenseAccount copyWith({
    String? id,
    String? name,
    String? accountCode,
    String? category,
  }) {
    return ExpenseAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      accountCode: accountCode ?? this.accountCode,
      category: category ?? this.category,
    );
  }

  @override
  List<Object?> get props => [id, name, accountCode, category];
}
