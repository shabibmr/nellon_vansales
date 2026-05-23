import '../../domain/models/open_invoice.dart';

class OpenInvoiceModel extends OpenInvoice {
  const OpenInvoiceModel({
    required super.invoiceId,
    required super.invoiceNumber,
    required super.customerId,
    required super.date,
    required super.dueDate,
    required super.total,
    required super.balance,
    required super.status,
  });

  factory OpenInvoiceModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return OpenInvoiceModel(
      invoiceId: json['invoice_id'] ?? json['invoiceId'] ?? '',
      invoiceNumber: json['invoice_number'] ?? json['invoiceNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      date: parseDate(json['date']),
      dueDate: parseDate(json['due_date'] ?? json['dueDate']),
      total: (json['total'] ?? 0.0).toDouble(),
      balance: (json['balance'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'unpaid',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'date': date.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'total': total,
      'balance': balance,
      'status': status,
    };
  }

  factory OpenInvoiceModel.fromDomain(OpenInvoice i) {
    return OpenInvoiceModel(
      invoiceId: i.invoiceId,
      invoiceNumber: i.invoiceNumber,
      customerId: i.customerId,
      date: i.date,
      dueDate: i.dueDate,
      total: i.total,
      balance: i.balance,
      status: i.status,
    );
  }
}
