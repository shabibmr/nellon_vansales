import '../../domain/models/sales_return.dart';
import 'sales_invoice_model.dart';

/// Data transfer object representing a [SalesReturnLineItem].
///
/// Converts credit note line details like items, return quantities, rates and nested invoices.
class SalesReturnLineItemModel extends SalesReturnLineItem {
  /// Creates a new [SalesReturnLineItemModel] instance.
  const SalesReturnLineItemModel({
    required super.invoiceLineItem,
    required super.returnedQuantity,
    super.invoiceId,
    super.invoiceNumber,
  });

  /// Factory constructor to parse local/remote JSON maps into a [SalesReturnLineItemModel].
  factory SalesReturnLineItemModel.fromJson(Map<String, dynamic> json) {
    return SalesReturnLineItemModel(
      invoiceLineItem: InvoiceLineItemModel.fromJson(
        json['invoiceLineItem'] ?? json,
      ),
      returnedQuantity: json['returned_quantity'] ?? json['quantity'] ?? 1,
      invoiceId: json['invoice_id'],
      invoiceNumber: json['invoice_number'],
    );
  }

  /// Converts this [SalesReturnLineItemModel] into a serialization compatible JSON map.
  Map<String, dynamic> toJson() {
    return {
      'item_id': invoiceLineItem.item.id,
      'quantity': returnedQuantity,
      'rate': invoiceLineItem.rate,
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'invoiceLineItem': InvoiceLineItemModel.fromDomain(
        invoiceLineItem,
      ).toJson(),
    };
  }

  /// Translates a base domain [SalesReturnLineItem] entity into its [SalesReturnLineItemModel] representation.
  factory SalesReturnLineItemModel.fromDomain(SalesReturnLineItem lineItem) {
    return SalesReturnLineItemModel(
      invoiceLineItem: lineItem.invoiceLineItem,
      returnedQuantity: lineItem.returnedQuantity,
      invoiceId: lineItem.invoiceId,
      invoiceNumber: lineItem.invoiceNumber,
    );
  }
}

/// Data transfer object representing a [SalesReturn] credit note log.
///
/// Translates credit note records, line item lists, and sync statuses into SQLite/Hive DB compatible JSON.
class SalesReturnModel extends SalesReturn {
  /// Creates a new [SalesReturnModel] instance.
  const SalesReturnModel({
    required super.id,
    required super.creditNoteNumber,
    required super.customerId,
    required super.customerName,
    required super.date,
    required super.items,
    required super.reason,
    super.isPendingSync,
    super.locationId,
  });

  /// Factory constructor to parse local database JSON maps into a [SalesReturnModel].
  factory SalesReturnModel.fromJson(Map<String, dynamic> json) {
    return SalesReturnModel(
      id: json['creditnote_id'] ?? json['id'] ?? '',
      creditNoteNumber:
          json['creditnote_number'] ?? json['creditNoteNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'])
          : DateTime.now(),
      items:
          (json['line_items'] as List?)
              ?.map((item) => SalesReturnLineItemModel.fromJson(item))
              .toList() ??
          [],
      reason: json['reason'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
      locationId: json['location_id'],
    );
  }

  /// Converts this [SalesReturnModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creditnote_id': id,
      'creditnote_number': creditNoteNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'date': date.toIso8601String().split('T')[0],
      'line_items': items
          .map((item) => SalesReturnLineItemModel.fromDomain(item).toJson())
          .toList(),
      'reason': reason,
      'isPendingSync': isPendingSync,
      'location_id': locationId,
    };
  }

  /// Translates a base domain [SalesReturn] entity into its [SalesReturnModel] representation.
  factory SalesReturnModel.fromDomain(SalesReturn salesReturn) {
    return SalesReturnModel(
      id: salesReturn.id,
      creditNoteNumber: salesReturn.creditNoteNumber,
      customerId: salesReturn.customerId,
      customerName: salesReturn.customerName,
      date: salesReturn.date,
      items: salesReturn.items,
      reason: salesReturn.reason,
      isPendingSync: salesReturn.isPendingSync,
      locationId: salesReturn.locationId,
    );
  }
}
