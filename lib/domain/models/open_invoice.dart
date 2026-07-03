import 'package:equatable/equatable.dart';

/// Lightweight snapshot of an unpaid invoice, synchronized from the server.
///
/// Used specifically for allocating payments locally/offline against particular outstanding
/// customer accounts during a route.
class OpenInvoice extends Equatable {
  /// Unique identifier of the invoice.
  final String invoiceId;

  /// Human-readable invoice voucher reference number.
  final String invoiceNumber;

  /// The customer ID this invoice was billed to.
  final String customerId;

  /// The date the invoice was generated.
  final DateTime date;

  /// The deadline date for invoice payment.
  final DateTime dueDate;

  /// The original grand total of the invoice.
  final double total;

  /// The remaining unpaid balance on this invoice.
  final double balance;

  /// The current payment state (e.g., "unpaid", "partially_paid", "overdue").
  final String status;

  /// Creates a new [OpenInvoice] snapshot.
  const OpenInvoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerId,
    required this.date,
    required this.dueDate,
    required this.total,
    required this.balance,
    required this.status,
  });

  /// Creates a copy of this [OpenInvoice] with replaced values for specific fields.
  OpenInvoice copyWith({
    String? invoiceId,
    String? invoiceNumber,
    String? customerId,
    DateTime? date,
    DateTime? dueDate,
    double? total,
    double? balance,
    String? status,
  }) {
    return OpenInvoice(
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      total: total ?? this.total,
      balance: balance ?? this.balance,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
    invoiceId,
    invoiceNumber,
    customerId,
    date,
    dueDate,
    total,
    balance,
    status,
  ];
}
