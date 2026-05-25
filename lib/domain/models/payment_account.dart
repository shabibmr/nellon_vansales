import 'package:equatable/equatable.dart';

/// Represents a Zoho Books financial account used to deposit collections.
///
/// Serves as the target `deposit_to` account mapping for local payment entries
/// (e.g. mapping cash, cheque, bank transfer, or card options to concrete ledgers).
class PaymentAccount extends Equatable {
  /// Unique account identifier from Zoho (account_id).
  final String id;

  /// Display name of the deposit/payment account.
  final String name;

  /// Classification type of the ledger (e.g. "bank", "cash", "other_current_asset").
  final String accountType;

  /// Primary currency code of the account (e.g. "USD", "AED").
  final String currencyCode;

  /// UI-facing label categorization (e.g., "Cash", "Cheque", "Bank Transfer", "Card").
  final String paymentMode;

  /// Creates a new [PaymentAccount] mapping.
  const PaymentAccount({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.paymentMode,
  });

  /// Creates a copy of this [PaymentAccount] with replaced values for specific fields.
  PaymentAccount copyWith({
    String? id,
    String? name,
    String? accountType,
    String? currencyCode,
    String? paymentMode,
  }) {
    return PaymentAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      currencyCode: currencyCode ?? this.currencyCode,
      paymentMode: paymentMode ?? this.paymentMode,
    );
  }

  @override
  List<Object?> get props => [id, name, accountType, currencyCode, paymentMode];
}

