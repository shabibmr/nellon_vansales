import '../../domain/models/payment_account.dart';

/// Data transfer object representing a deposit [PaymentAccount].
///
/// Directs serialization of Zoho Chart of Accounts ledger structures for collection entry mapping.
class PaymentAccountModel extends PaymentAccount {
  /// Creates a new [PaymentAccountModel] instance.
  const PaymentAccountModel({
    required super.id,
    required super.name,
    required super.accountType,
    required super.currencyCode,
    required super.paymentMode,
  });

  /// Factory constructor to parse local/remote JSON maps into a [PaymentAccountModel].
  ///
  /// Mappes Zoho ledger fields (`account_id`, `account_name`, `account_type`, `currency_code`, `payment_mode`) with fallback defaults.
  factory PaymentAccountModel.fromJson(Map<String, dynamic> json) {
    return PaymentAccountModel(
      id: json['account_id'] ?? json['id'] ?? '',
      name: json['account_name'] ?? json['name'] ?? '',
      accountType: json['account_type'] ?? json['accountType'] ?? 'bank',
      currencyCode: json['currency_code'] ?? json['currencyCode'] ?? '',
      paymentMode: json['payment_mode'] ?? json['paymentMode'] ?? '',
    );
  }

  /// Converts this [PaymentAccountModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': id,
      'name': name,
      'account_name': name,
      'account_type': accountType,
      'currency_code': currencyCode,
      'payment_mode': paymentMode,
    };
  }

  /// Translates a base domain [PaymentAccount] entity into a serializable [PaymentAccountModel].
  factory PaymentAccountModel.fromDomain(PaymentAccount a) {
    return PaymentAccountModel(
      id: a.id,
      name: a.name,
      accountType: a.accountType,
      currencyCode: a.currencyCode,
      paymentMode: a.paymentMode,
    );
  }
}
