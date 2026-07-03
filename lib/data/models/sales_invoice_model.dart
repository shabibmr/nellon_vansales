import '../../domain/models/sales_invoice.dart';
import 'item_model.dart';

/// Data transfer object representing an [InvoiceLineItem].
///
/// Handles converting specific invoice row mappings, stock SKUs, and tax percentages to backend schemas.
class InvoiceLineItemModel extends InvoiceLineItem {
  /// Creates a new [InvoiceLineItemModel] instance.
  const InvoiceLineItemModel({
    required super.item,
    required super.quantity,
    required super.rate,
    required super.taxPercentage,
    super.discount = 0.0,
  });

  /// Factory constructor to parse local/remote JSON maps into an [InvoiceLineItemModel].
  factory InvoiceLineItemModel.fromJson(Map<String, dynamic> json) {
    return InvoiceLineItemModel(
      item: ItemModel.fromJson(json['item'] ?? json),
      quantity: json['quantity'] ?? 1,
      rate: (json['rate'] ?? 0.0).toDouble(),
      taxPercentage: (json['tax_percentage'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? 0.0).toDouble(),
    );
  }

  /// Converts this [InvoiceLineItemModel] into a serialization compatible JSON map.
  Map<String, dynamic> toJson() {
    return {
      'item_id': item.id,
      'quantity': quantity,
      'rate': rate,
      'tax_percentage': taxPercentage,
      'discount': discount,
      'item': ItemModel.fromDomain(item).toJson(),
    };
  }

  /// Translates a base domain [InvoiceLineItem] entity into its [InvoiceLineItemModel] DTO representation.
  factory InvoiceLineItemModel.fromDomain(InvoiceLineItem lineItem) {
    return InvoiceLineItemModel(
      item: lineItem.item,
      quantity: lineItem.quantity,
      rate: lineItem.rate,
      taxPercentage: lineItem.taxPercentage,
      discount: lineItem.discount,
    );
  }
}

/// Data transfer object representing a [SalesInvoice] voucher.
///
/// Marshals invoice rows, customer metadata, and sync flags into a database format.
class SalesInvoiceModel extends SalesInvoice {
  /// Creates a new [SalesInvoiceModel] instance.
  const SalesInvoiceModel({
    required super.id,
    required super.invoiceNumber,
    required super.customerId,
    required super.customerName,
    required super.date,
    required super.dueDate,
    required super.items,
    required super.notes,
    super.isPendingSync,
  });

  /// Factory constructor to parse local database JSON maps into a [SalesInvoiceModel].
  factory SalesInvoiceModel.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceModel(
      id: json['invoice_id'] ?? json['id'] ?? '',
      invoiceNumber: json['invoice_number'] ?? json['invoiceNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : DateTime.now(),
      items: (json['line_items'] as List?)
              ?.map((item) => InvoiceLineItemModel.fromJson(item))
              .toList() ??
          [],
      notes: json['notes'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

  /// Converts this [SalesInvoiceModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoice_id': id,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'date': date.toIso8601String().split('T')[0],
      'due_date': dueDate.toIso8601String().split('T')[0],
      'line_items': items
          .map((item) => InvoiceLineItemModel.fromDomain(item).toJson())
          .toList(),
      'notes': notes,
      'isPendingSync': isPendingSync,
      'round_off': roundOff,
    };
  }

  /// Translates a base domain [SalesInvoice] entity into its [SalesInvoiceModel] representation.
  factory SalesInvoiceModel.fromDomain(SalesInvoice invoice) {
    return SalesInvoiceModel(
      id: invoice.id,
      invoiceNumber: invoice.invoiceNumber,
      customerId: invoice.customerId,
      customerName: invoice.customerName,
      date: invoice.date,
      dueDate: invoice.dueDate,
      items: invoice.items,
      notes: invoice.notes,
      isPendingSync: invoice.isPendingSync,
    );
  }
}

