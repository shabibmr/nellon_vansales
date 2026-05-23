import 'package:equatable/equatable.dart';

/// Lightweight snapshot of an unpaid invoice — used for receipt allocation
/// against a customer when offline. Refreshed per route load.
class OpenInvoice extends Equatable {
  final String invoiceId;
  final String invoiceNumber;
  final String customerId;
  final DateTime date;
  final DateTime dueDate;
  final double total;
  final double balance;
  final String status; // unpaid | partially_paid | overdue

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
  List<Object?> get props =>
      [invoiceId, invoiceNumber, customerId, date, dueDate, total, balance, status];
}
