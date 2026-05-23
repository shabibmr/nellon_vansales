import 'package:equatable/equatable.dart';

/// A Zoho Books bank or cash ledger used as `deposit_to` when creating
/// a customer payment. The van app maps each UI payment mode
/// (Cash / Cheque / Bank Transfer / Card) to one of these accounts.
class PaymentAccount extends Equatable {
  final String id; // Zoho account_id
  final String name;
  final String accountType; // bank | cash | other_current_asset
  final String currencyCode;
  final String paymentMode; // UI-facing label: Cash, Cheque, Bank Transfer, Card

  const PaymentAccount({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.paymentMode,
  });

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
