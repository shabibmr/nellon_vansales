import '../../domain/models/open_invoice.dart';

/// Data transfer object representing an [OpenInvoice] outstanding billing record.
///
/// Implements date parsers and bridges remote Zoho Books Invoice API responses for offline collection sheets.
class OpenInvoiceModel extends OpenInvoice {
  /// Creates a new [OpenInvoiceModel] instance.
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

  /// Factory constructor to parse local/remote JSON maps into an [OpenInvoiceModel].
  ///
  /// Mappes keys (`invoice_id`, `invoice_number`, `customer_id`, `due_date`) cleanly with dynamic date parsers.
  factory OpenInvoiceModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    double parseMoney(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return OpenInvoiceModel(
      invoiceId: ((json['invoice_id'] ?? json['invoiceId']) as String?) ?? '',
      invoiceNumber: ((json['invoice_number'] ?? json['invoiceNumber']) as String?) ?? '',
      customerId: ((json['customer_id'] ?? json['customerId']) as String?) ?? '',
      date: parseDate(json['date']),
      dueDate: parseDate(json['due_date'] ?? json['dueDate']),
      total: parseMoney(json['total']),
      balance: parseMoney(json['balance']),
      status: (json['status'] as String?) ?? 'unpaid',
    );
  }

  /// Converts this [OpenInvoiceModel] instance into a serializable JSON map.
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

  /// Translates a base domain [OpenInvoice] entity into its [OpenInvoiceModel] DTO representation.
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
