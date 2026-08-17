import '../../domain/models/sales_return.dart';
import 'json_read.dart';
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
    super.uom = '',
    super.unitConversionId = '',
  });

  /// Factory constructor to parse local/remote JSON maps into a [SalesReturnLineItemModel].
  factory SalesReturnLineItemModel.fromJson(Map<String, dynamic> json) {
    final nested = Map<String, dynamic>.from(
      (json['invoiceLineItem'] as Map?) ?? json,
    );
    final invoiceItemId = (json['invoice_item_id'] ?? nested['line_item_id'])
        ?.toString();
    if (invoiceItemId != null && invoiceItemId.isNotEmpty) {
      nested['line_item_id'] = invoiceItemId;
    }
    return SalesReturnLineItemModel(
      invoiceLineItem: InvoiceLineItemModel.fromJson(nested),
      returnedQuantity: ((json['returned_quantity'] ?? json['quantity'] ?? 1)
              as num)
          .toDouble(),
      invoiceId: jsonStringOrNull(json['invoice_id']),
      invoiceNumber: jsonStringOrNull(json['invoice_number']),
      uom: (json['return_uom'] ?? '').toString(),
      unitConversionId: (json['unit_conversion_id'] ?? '').toString(),
    );
  }

  /// Converts this [SalesReturnLineItemModel] into a serialization compatible JSON map.
  ///
  /// `quantity`, `rate`, `unit` are expressed in the selected return unit —
  /// the Zoho credit-note mapper whitelists them directly.
  Map<String, dynamic> toJson() {
    final unit = displayUom;
    final taxId = invoiceLineItem.item.taxId;
    return {
      'item_id': invoiceLineItem.item.id,
      'quantity': returnedQuantity,
      'rate': rate,
      'tax_percentage': invoiceLineItem.taxPercentage,
      if (taxId.isNotEmpty) 'tax_id': taxId,
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      if (unit.isNotEmpty) 'unit': unit,
      // Local-only key so fromJson can distinguish the line's own uom
      // override from the nested invoice line's unit.
      if (uom.isNotEmpty) 'return_uom': uom,
      if (unitConversionId.isNotEmpty) 'unit_conversion_id': unitConversionId,
      if (invoiceLineItem.lineItemId.isNotEmpty)
        'invoice_item_id': invoiceLineItem.lineItemId,
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
      uom: lineItem.uom,
      unitConversionId: lineItem.unitConversionId,
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
    super.zohoCreditNoteId,
    super.locationId,
    super.listedTotal,
  });

  /// Factory constructor to parse local database JSON maps into a [SalesReturnModel].
  factory SalesReturnModel.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'] ?? json['listedTotal'];
    double? listedTotal;
    if (rawTotal is num) {
      listedTotal = rawTotal.toDouble();
    } else if (rawTotal != null) {
      listedTotal = double.tryParse(rawTotal.toString());
    }

    return SalesReturnModel(
      id: jsonString(json['creditnote_id'] ?? json['id']),
      creditNoteNumber:
          jsonString(json['creditnote_number'] ?? json['creditNoteNumber']),
      customerId: jsonString(json['customer_id'] ?? json['customerId']),
      customerName: jsonString(json['customer_name'] ?? json['customerName']),
      date: jsonDate(json['date']),
      items:
          jsonList(json['line_items'])
              .map((item) => SalesReturnLineItemModel.fromJson(jsonMap(item)))
              .toList(),
      reason: jsonString(
          json['reason'] ??
          json['reason_for_credit_debit_note'] ??
          json['notes']),
      isPendingSync: jsonBool(json['isPendingSync']),
      zohoCreditNoteId: jsonStringOrNull(json['zoho_credit_note_id'] ?? json['zohoCreditNoteId']),
      locationId: jsonStringOrNull(json['location_id']),
      listedTotal: listedTotal,
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
      'zoho_credit_note_id': zohoCreditNoteId,
      'location_id': locationId,
      if (listedTotal != null) 'total': listedTotal,
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
      zohoCreditNoteId: salesReturn.zohoCreditNoteId,
      locationId: salesReturn.locationId,
      listedTotal: salesReturn.listedTotal,
    );
  }
}
