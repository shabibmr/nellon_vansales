import '../../domain/models/receipt_voucher.dart';

class PaymentAllocationModel extends PaymentAllocation {
  const PaymentAllocationModel({
    required super.invoiceId,
    required super.invoiceNumber,
    required super.amountApplied,
  });

  factory PaymentAllocationModel.fromJson(Map<String, dynamic> json) {
    return PaymentAllocationModel(
      invoiceId: json['invoice_id'] ?? json['invoiceId'] ?? '',
      invoiceNumber: json['invoice_number'] ?? json['invoiceNumber'] ?? '',
      amountApplied: (json['amount_applied'] ?? json['amountApplied'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'amount_applied': amountApplied,
    };
  }

  factory PaymentAllocationModel.fromDomain(PaymentAllocation domain) {
    return PaymentAllocationModel(
      invoiceId: domain.invoiceId,
      invoiceNumber: domain.invoiceNumber,
      amountApplied: domain.amountApplied,
    );
  }
}

class ReceiptVoucherModel extends ReceiptVoucher {
  const ReceiptVoucherModel({
    required super.id,
    required super.paymentNumber,
    required super.customerId,
    required super.customerName,
    required super.allocations,
    required super.amount,
    required super.paymentMode,
    required super.referenceNumber,
    required super.date,
    super.isPendingSync,
  });

  factory ReceiptVoucherModel.fromJson(Map<String, dynamic> json) {
    return ReceiptVoucherModel(
      id: json['payment_id'] ?? json['id'] ?? '',
      paymentNumber: json['payment_number'] ?? json['paymentNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      allocations: (json['invoices'] as List?)
              ?.map((item) => PaymentAllocationModel.fromJson(item))
              .toList() ??
          [],
      amount: (json['amount'] ?? 0.0).toDouble(),
      paymentMode: json['payment_mode'] ?? json['paymentMode'] ?? 'Cash',
      referenceNumber: json['reference_number'] ?? json['referenceNumber'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'payment_id': id,
      'payment_number': paymentNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'amount': amount,
      'payment_mode': paymentMode,
      'reference_number': referenceNumber,
      'date': date.toIso8601String().split('T')[0],
      'isPendingSync': isPendingSync,
      'invoices': allocations
          .map((item) => PaymentAllocationModel.fromDomain(item).toJson())
          .toList(),
    };
  }

  factory ReceiptVoucherModel.fromDomain(ReceiptVoucher voucher) {
    return ReceiptVoucherModel(
      id: voucher.id,
      paymentNumber: voucher.paymentNumber,
      customerId: voucher.customerId,
      customerName: voucher.customerName,
      allocations: voucher.allocations,
      amount: voucher.amount,
      paymentMode: voucher.paymentMode,
      referenceNumber: voucher.referenceNumber,
      date: voucher.date,
      isPendingSync: voucher.isPendingSync,
    );
  }
}
