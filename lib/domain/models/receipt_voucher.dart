import 'package:equatable/equatable.dart';

/// Represents a specific application of cash or payment against an outstanding open invoice.
class PaymentAllocation extends Equatable {
  /// The invoice ID to which this payment is applied.
  final String invoiceId;

  /// The reference number of the target invoice.
  final String invoiceNumber;

  /// The partial or full amount of payment allocated to this invoice.
  final double amountApplied;

  /// Creates a new [PaymentAllocation] item.
  const PaymentAllocation({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.amountApplied,
  });

  @override
  List<Object?> get props => [invoiceId, invoiceNumber, amountApplied];
}

/// Represents a customer receipt voucher generated during collection.
///
/// Receipts can be allocated across multiple outstanding invoices via [PaymentAllocation] list,
/// leaving any unallocated amount as general customer deposit credit.
class ReceiptVoucher extends Equatable {
  /// Unique identifier of the receipt voucher.
  final String id;

  /// Official payment number sequence assigned locally.
  final String paymentNumber;

  /// Customer identifier.
  final String customerId;

  /// Display name of the customer.
  final String customerName;

  /// Collection of invoice allocations for this payment.
  final List<PaymentAllocation> allocations;

  /// Grand total received from the customer.
  final double amount;

  /// Payment method category (e.g. "Cash", "Cheque", "Bank Transfer", "Card").
  final String paymentMode;

  /// Manual reference identifier (e.g. Cheque number, Transaction ID).
  final String referenceNumber;

  /// Timestamp when the receipt was created.
  final DateTime date;

  /// Flag indicating if the collection is pending backend synchronization.
  final bool isPendingSync;

  /// Creates a new [ReceiptVoucher].
  const ReceiptVoucher({
    required this.id,
    required this.paymentNumber,
    required this.customerId,
    required this.customerName,
    required this.allocations,
    required this.amount,
    required this.paymentMode,
    required this.referenceNumber,
    required this.date,
    this.isPendingSync = false,
  });

  /// Calculates the sum of all allocations applied to specific invoices.
  double get totalAllocated =>
      allocations.fold(0.0, (sum, item) => sum + item.amountApplied);

  /// Calculates the excess/remaining amount of payment that acts as a customer credit.
  double get unallocatedAmount => amount - totalAllocated;

  /// Creates a copy of this [ReceiptVoucher] with replaced values for specific fields.
  ReceiptVoucher copyWith({
    String? id,
    String? paymentNumber,
    String? customerId,
    String? customerName,
    List<PaymentAllocation>? allocations,
    double? amount,
    String? paymentMode,
    String? referenceNumber,
    DateTime? date,
    bool? isPendingSync,
  }) {
    return ReceiptVoucher(
      id: id ?? this.id,
      paymentNumber: paymentNumber ?? this.paymentNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      allocations: allocations ?? this.allocations,
      amount: amount ?? this.amount,
      paymentMode: paymentMode ?? this.paymentMode,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      date: date ?? this.date,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => [
    id,
    paymentNumber,
    customerId,
    customerName,
    allocations,
    amount,
    paymentMode,
    referenceNumber,
    date,
    isPendingSync,
  ];
}
