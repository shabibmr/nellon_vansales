import '../../domain/models/receipt_voucher.dart';
import 'json_read.dart';

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
      invoiceId: jsonString(json['invoice_id'] ?? json['invoiceId']),
      invoiceNumber: jsonString(json['invoice_number'] ?? json['invoiceNumber']),
      amountApplied: jsonDouble(json['amount_applied'] ?? json['amountApplied']),
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
    super.zohoPaymentId,
    super.locationId,
    super.salespersonId,
  });

  /// Factory constructor to parse local database JSON maps into a [ReceiptVoucherModel].
  factory ReceiptVoucherModel.fromJson(Map<String, dynamic> json) {
    final zohoPaymentNumber =
        (json['payment_number'] ?? json['paymentNumber'] ?? '').toString();
    final referenceNumber =
        (json['reference_number'] ?? json['referenceNumber'] ?? '').toString();
    // App series number travels to Zoho as reference_number (B4). Prefer it as
    // the display/identity number when present so list UI and session filters
    // see `{prefix}RCT-#####` rather than Zoho's auto payment_number.
    final seriesInReference = referenceNumber.contains('RCT-');
    return ReceiptVoucherModel(
      id: jsonString(json['payment_id'] ?? json['id']),
      paymentNumber:
          seriesInReference && referenceNumber.isNotEmpty
              ? referenceNumber
              : zohoPaymentNumber,
      customerId: jsonString(json['customer_id'] ?? json['customerId']),
      customerName: jsonString(json['customer_name'] ?? json['customerName']),
      allocations:
          jsonList(json['invoices'])
              .map((item) => PaymentAllocationModel.fromJson(jsonMap(item)))
              .toList(),
      amount: jsonDouble(json['amount']),
      paymentMode: jsonString(json['payment_mode'] ?? json['paymentMode'], 'Cash'),
      referenceNumber: referenceNumber,
      date: jsonDate(json['date']),
      isPendingSync: jsonBool(json['isPendingSync']),
      zohoPaymentId: jsonStringOrNull(json['zoho_payment_id'] ?? json['zohoPaymentId']),
      locationId: jsonStringOrNull(json['location_id']),
      // Zoho key is `sales_person_id` (underscore-separated) — different from
      // the `salesperson_id` used by invoices/orders/creditnotes.
      salespersonId: (json['sales_person_id'] ?? json['salespersonId'])
          ?.toString(),
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
      'zoho_payment_id': zohoPaymentId,
      'location_id': locationId,
      'sales_person_id': salespersonId,
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
      zohoPaymentId: voucher.zohoPaymentId,
      locationId: voucher.locationId,
      salespersonId: voucher.salespersonId,
    );
  }
}
