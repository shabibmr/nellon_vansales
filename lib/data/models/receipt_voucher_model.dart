import '../../domain/models/receipt_voucher.dart';

/// Data transfer object representing a [PaymentAllocation] entry.
///
/// Maps payment allocations to individual outstanding invoices when posting payment records.
class PaymentAllocationModel extends PaymentAllocation {
  /// Creates a new [PaymentAllocationModel] instance.
  const PaymentAllocationModel({
    required super.invoiceId,
    required super.invoiceNumber,
    required super.amountApplied,
  });

  /// Factory constructor to parse local/remote JSON maps into a [PaymentAllocationModel].
  factory PaymentAllocationModel.fromJson(Map<String, dynamic> json) {
    return PaymentAllocationModel(
      invoiceId: json['invoice_id'] ?? json['invoiceId'] ?? '',
      invoiceNumber: json['invoice_number'] ?? json['invoiceNumber'] ?? '',
      amountApplied: (json['amount_applied'] ?? json['amountApplied'] ?? 0.0).toDouble(),
    );
  }

  /// Converts this [PaymentAllocationModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'amount_applied': amountApplied,
    };
  }

  /// Translates a base domain [PaymentAllocation] entity into its [PaymentAllocationModel] DTO representation.
  factory PaymentAllocationModel.fromDomain(PaymentAllocation domain) {
    return PaymentAllocationModel(
      invoiceId: domain.invoiceId,
      invoiceNumber: domain.invoiceNumber,
      amountApplied: domain.amountApplied,
    );
  }
}

/// Data transfer object representing a [ReceiptVoucher] collection voucher.
///
/// Maps customer payments, multi-invoice allocations, and sync parameters for database storage and background uploading.
class ReceiptVoucherModel extends ReceiptVoucher {
  /// Creates a new [ReceiptVoucherModel] instance.
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

  /// Factory constructor to parse local database JSON maps into a [ReceiptVoucherModel].
  factory ReceiptVoucherModel.fromJson(Map<String, dynamic> json) {
    return ReceiptVoucherModel(
      id: json['payment_id'] ?? json['id'] ?? '',
      paymentNumber: json['payment_number'] ?? json['paymentNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      // Parses list of dynamic invoice objects into [PaymentAllocationModel] list.
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

  /// Converts this [ReceiptVoucherModel] instance into a serializable JSON map.
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
      // Transforms domain allocations back into JSON representation for storage.
      'invoices': allocations
          .map((item) => PaymentAllocationModel.fromDomain(item).toJson())
          .toList(),
    };
  }

  /// Translates a base domain [ReceiptVoucher] entity into its [ReceiptVoucherModel] representation.
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
