import 'package:equatable/equatable.dart';

/// Represents a Zoho Books expense ledger account.
///
/// The mobile application maps each local user-interface expense category
/// (e.g., Fuel, Tolls, Meals, Maintenance, Miscellaneous) to one of these concrete accounts
/// for bookkeeping alignment.
class ExpenseAccount extends Equatable {
  /// Unique ledger account identifier from Zoho (account_id).
  final String id;

  /// The official name of the expense ledger account.
  final String name;

  /// System account code associated with this ledger.
  final String accountCode;

  /// The user-facing classification category label.
  final String category;

  /// Creates a new [ExpenseAccount] mapping ledger.
  const ExpenseAccount({
    required this.id,
    required this.name,
    required this.accountCode,
    required this.category,
  });

  /// Creates a copy of this [ExpenseAccount] with replaced values for specific fields.
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

