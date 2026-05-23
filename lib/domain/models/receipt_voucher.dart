import 'package:equatable/equatable.dart';

class PaymentAllocation extends Equatable {
  final String invoiceId;
  final String invoiceNumber;
  final double amountApplied;

  const PaymentAllocation({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.amountApplied,
  });

  @override
  List<Object?> get props => [invoiceId, invoiceNumber, amountApplied];
}

class ReceiptVoucher extends Equatable {
  final String id;
  final String paymentNumber;
  final String customerId;
  final String customerName;
  final List<PaymentAllocation> allocations; // Allocated across multiple invoices
  final double amount;
  final String paymentMode; // Cash, Cheque, Bank Transfer, Card
  final String referenceNumber;
  final DateTime date;
  final bool isPendingSync;

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

  // Calculate sum of applied allocations
  double get totalAllocated => allocations.fold(0.0, (sum, item) => sum + item.amountApplied);
  double get unallocatedAmount => amount - totalAllocated;

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
