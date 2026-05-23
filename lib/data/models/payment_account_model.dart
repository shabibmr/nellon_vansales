import '../../domain/models/payment_account.dart';

class PaymentAccountModel extends PaymentAccount {
  const PaymentAccountModel({
    required super.id,
    required super.name,
    required super.accountType,
    required super.currencyCode,
    required super.paymentMode,
  });

  factory PaymentAccountModel.fromJson(Map<String, dynamic> json) {
    return PaymentAccountModel(
      id: json['account_id'] ?? json['id'] ?? '',
      name: json['account_name'] ?? json['name'] ?? '',
      accountType: json['account_type'] ?? json['accountType'] ?? 'bank',
      currencyCode: json['currency_code'] ?? json['currencyCode'] ?? '',
      paymentMode: json['payment_mode'] ?? json['paymentMode'] ?? '',
    );
  }

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
