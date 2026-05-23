import '../../domain/models/sales_return.dart';
import 'sales_invoice_model.dart';

class SalesReturnLineItemModel extends SalesReturnLineItem {
  const SalesReturnLineItemModel({
    required super.invoiceLineItem,
    required super.returnedQuantity,
  });

  factory SalesReturnLineItemModel.fromJson(Map<String, dynamic> json) {
    return SalesReturnLineItemModel(
      invoiceLineItem: InvoiceLineItemModel.fromJson(json['invoiceLineItem'] ?? json),
      returnedQuantity: json['returned_quantity'] ?? json['quantity'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': invoiceLineItem.item.id,
      'quantity': returnedQuantity,
      'rate': invoiceLineItem.rate,
      'invoiceLineItem': InvoiceLineItemModel.fromDomain(invoiceLineItem).toJson(),
    };
  }

  factory SalesReturnLineItemModel.fromDomain(SalesReturnLineItem lineItem) {
    return SalesReturnLineItemModel(
      invoiceLineItem: lineItem.invoiceLineItem,
      returnedQuantity: lineItem.returnedQuantity,
    );
  }
}

class SalesReturnModel extends SalesReturn {
  const SalesReturnModel({
    required super.id,
    required super.creditNoteNumber,
    required super.customerId,
    required super.customerName,
    required super.date,
    required super.items,
    required super.reason,
    super.isPendingSync,
  });

  factory SalesReturnModel.fromJson(Map<String, dynamic> json) {
    return SalesReturnModel(
      id: json['creditnote_id'] ?? json['id'] ?? '',
      creditNoteNumber: json['creditnote_number'] ?? json['creditNoteNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      items: (json['line_items'] as List?)
              ?.map((item) => SalesReturnLineItemModel.fromJson(item))
              .toList() ??
          [],
      reason: json['reason'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

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
    };
  }

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
    );
  }
}
