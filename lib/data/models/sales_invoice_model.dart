import '../../domain/models/sales_invoice.dart';
import 'item_model.dart';

/// Parses a JSON value that may be a [num] or a numeric [String] (Zoho
/// sometimes returns line-item numeric fields as strings).
double _parseNum(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

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
    super.uom = '',
    super.unitConversionId = '',
  });

  /// Factory constructor to parse local/remote JSON maps into an [InvoiceLineItemModel].
  factory InvoiceLineItemModel.fromJson(Map<String, dynamic> json) {
    var item = ItemModel.fromJson(json['item'] ?? json);
    // Line-level tax fields win when Zoho returns them only on the line.
    final lineTaxId = (json['tax_id'] ?? '').toString();
    final lineTaxName = (json['tax_name'] ?? '').toString();
    if (lineTaxId.isNotEmpty || lineTaxName.isNotEmpty) {
      item = ItemModel.fromDomain(
        item.copyWith(
          taxId: lineTaxId.isNotEmpty ? lineTaxId : null,
          taxName: lineTaxName.isNotEmpty ? lineTaxName : null,
          taxPercentage: json['tax_percentage'] != null
              ? _parseNum(json['tax_percentage'])
              : null,
        ),
      );
    }
    final lineUom = (json['unit'] ?? json['uom'] ?? '').toString();
    return InvoiceLineItemModel(
      item: item,
      quantity: _parseNum(json['quantity'], 1.0),
      rate: _parseNum(json['rate']),
      taxPercentage: json['tax_percentage'] != null
          ? _parseNum(json['tax_percentage'])
          : item.taxPercentage,
      discount: _parseNum(json['discount_amount'] ?? json['discount']),
      uom: lineUom.isNotEmpty ? lineUom : item.uom,
      unitConversionId: (json['unit_conversion_id'] ?? '').toString(),
    );
  }

  /// Converts this [InvoiceLineItemModel] into a serialization compatible JSON map.
  Map<String, dynamic> toJson() {
    final unit = displayUom;
    final taxId = item.taxId;
    return {
      'item_id': item.id,
      'quantity': quantity,
      'rate': rate,
      'tax_percentage': taxPercentage,
      if (taxId.isNotEmpty) 'tax_id': taxId,
      'discount': discount,
      if (unit.isNotEmpty) 'unit': unit,
      if (unit.isNotEmpty) 'uom': unit,
      if (unitConversionId.isNotEmpty) 'unit_conversion_id': unitConversionId,
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
      uom: lineItem.uom.isNotEmpty ? lineItem.uom : lineItem.item.uom,
      unitConversionId: lineItem.unitConversionId,
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
    super.locationId,
    super.status,
    super.listedTotal,
  });

  /// Factory constructor to parse local database JSON maps into a [SalesInvoiceModel].
  factory SalesInvoiceModel.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'] ?? json['listedTotal'];
    double? listedTotal;
    if (rawTotal is num) {
      listedTotal = rawTotal.toDouble();
    } else if (rawTotal != null) {
      listedTotal = double.tryParse(rawTotal.toString());
    }

    return SalesInvoiceModel(
      id: json['invoice_id'] ?? json['id'] ?? '',
      invoiceNumber: json['invoice_number'] ?? json['invoiceNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'])
          : DateTime.now(),
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'])
          : DateTime.now(),
      items:
          (json['line_items'] as List?)
              ?.map((item) => InvoiceLineItemModel.fromJson(item))
              .toList() ??
          [],
      notes: json['notes'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
      locationId: json['location_id'],
      status: (json['status'] ?? '').toString(),
      listedTotal: listedTotal,
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
      'location_id': locationId,
      'status': status,
      if (listedTotal != null) 'total': listedTotal,
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
      locationId: invoice.locationId,
      status: invoice.status,
      listedTotal: invoice.listedTotal,
    );
  }
}
