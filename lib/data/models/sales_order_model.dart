import '../../domain/models/sales_order.dart';
import 'item_model.dart';
import 'json_read.dart';

/// Data transfer object representing an [OrderLineItem].
///
/// Handles converting specific order row mappings, stock SKUs, and tax percentages to backend schemas.
class OrderLineItemModel extends OrderLineItem {
  /// Creates a new [OrderLineItemModel] instance.
  const OrderLineItemModel({
    required super.item,
    required super.quantity,
    required super.rate,
    required super.taxPercentage,
    super.discount = 0.0,
    super.uom = '',
    super.unitConversionId = '',
  });

  /// Factory constructor to parse local/remote JSON maps into an [OrderLineItemModel].
  factory OrderLineItemModel.fromJson(Map<String, dynamic> json) {
    var item = ItemModel.fromJson(jsonMap(json['item'] ?? json));
    // Line-level tax fields win when Zoho returns them only on the line.
    final lineTaxId = (json['tax_id'] ?? '').toString();
    final lineTaxName = (json['tax_name'] ?? '').toString();
    if (lineTaxId.isNotEmpty || lineTaxName.isNotEmpty) {
      item = ItemModel.fromDomain(
        item.copyWith(
          taxId: lineTaxId.isNotEmpty ? lineTaxId : null,
          taxName: lineTaxName.isNotEmpty ? lineTaxName : null,
          taxPercentage: json['tax_percentage'] != null
              ? (json['tax_percentage'] as num).toDouble()
              : null,
        ),
      );
    }
    final lineUom = (json['unit'] ?? json['uom'] ?? '').toString();
    return OrderLineItemModel(
      item: item,
      quantity: jsonDouble(json['quantity'], 1.0),
      rate: jsonDouble(json['rate']),
      taxPercentage: jsonDouble(json['tax_percentage'], item.taxPercentage),
      discount: jsonDouble(json['discount']),
      uom: lineUom.isNotEmpty ? lineUom : item.uom,
      unitConversionId: (json['unit_conversion_id'] ?? '').toString(),
    );
  }

  /// Converts this [OrderLineItemModel] into a serialization compatible JSON map.
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

  /// Translates a base domain [OrderLineItem] entity into its [OrderLineItemModel] DTO representation.
  factory OrderLineItemModel.fromDomain(OrderLineItem lineItem) {
    return OrderLineItemModel(
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

/// Data transfer object representing a [SalesOrder] voucher.
///
/// Marshals order rows, customer metadata, and sync flags into a database format.
class SalesOrderModel extends SalesOrder {
  /// Creates a new [SalesOrderModel] instance.
  const SalesOrderModel({
    required super.id,
    required super.orderNumber,
    required super.customerId,
    required super.customerName,
    required super.date,
    required super.shipmentDate,
    required super.items,
    required super.notes,
    super.isPendingSync,
    super.status,
    super.convertedInvoiceNumber,
    super.zohoOrderId,
    super.locationId,
    super.listedTotal,
    super.orderStatus,
    super.invoicedStatus,
    super.referenceNumber,
  });

  /// Factory constructor to parse local database JSON maps into a [SalesOrderModel].
  factory SalesOrderModel.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'] ?? json['listedTotal'];
    double? listedTotal;
    if (rawTotal is num) {
      listedTotal = rawTotal.toDouble();
    } else if (rawTotal != null) {
      listedTotal = double.tryParse(rawTotal.toString());
    }

    final orderStatus = (json['order_status'] ?? json['orderStatus'] ?? '')
        .toString();
    final invoicedStatus =
        (json['invoiced_status'] ?? json['invoicedStatus'] ?? '').toString();
    final referenceNumber =
        (json['reference_number'] ?? json['referenceNumber'] ?? '').toString();

    return SalesOrderModel(
      id: jsonString(json['salesorder_id'] ?? json['id']),
      orderNumber: jsonString(json['salesorder_number'] ?? json['orderNumber']),
      customerId: jsonString(json['customer_id'] ?? json['customerId']),
      customerName: jsonString(json['customer_name'] ?? json['customerName']),
      date: jsonDate(json['date']),
      shipmentDate: jsonDate(json['shipment_date']),
      items:
          jsonList(json['line_items'])
              .map((item) => OrderLineItemModel.fromJson(jsonMap(item)))
              .toList(),
      notes: jsonString(json['notes']),
      isPendingSync: jsonBool(json['isPendingSync']),
      status: _statusFromZohoFields(
        status: json['status'],
        orderStatus: orderStatus,
        invoicedStatus: invoicedStatus,
      ),
      convertedInvoiceNumber: jsonStringOrNull(json['converted_invoice_number']),
      zohoOrderId: jsonStringOrNull(json['zoho_order_id']),
      locationId: jsonStringOrNull(json['location_id']),
      listedTotal: listedTotal,
      orderStatus: orderStatus,
      invoicedStatus: invoicedStatus,
      referenceNumber: referenceNumber,
    );
  }

  /// Maps Zoho `status` / `order_status` / `invoiced_status` into the app's
  /// two-value [SalesOrderStatus]. Any field equal to `invoiced` wins.
  static SalesOrderStatus _statusFromZohoFields({
    dynamic status,
    required String orderStatus,
    required String invoicedStatus,
  }) {
    bool isInvoiced(dynamic v) =>
        v?.toString().toLowerCase().trim() == 'invoiced';
    if (isInvoiced(status) ||
        isInvoiced(orderStatus) ||
        isInvoiced(invoicedStatus)) {
      return SalesOrderStatus.invoiced;
    }
    return SalesOrderStatus.open;
  }

  /// Converts this [SalesOrderModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'salesorder_id': id,
      'salesorder_number': orderNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'date': date.toIso8601String().split('T')[0],
      'shipment_date': shipmentDate.toIso8601String().split('T')[0],
      'line_items': items
          .map((item) => OrderLineItemModel.fromDomain(item).toJson())
          .toList(),
      'notes': notes,
      'isPendingSync': isPendingSync,
      'round_off': roundOff,
      'status': status == SalesOrderStatus.invoiced ? 'invoiced' : 'open',
      'order_status': orderStatus,
      'invoiced_status': invoicedStatus,
      'reference_number': referenceNumber,
      'converted_invoice_number': convertedInvoiceNumber,
      'zoho_order_id': zohoOrderId,
      'location_id': locationId,
      if (listedTotal != null) 'total': listedTotal,
    };
  }

  /// Translates a base domain [SalesOrder] entity into its [SalesOrderModel] representation.
  factory SalesOrderModel.fromDomain(SalesOrder order) {
    return SalesOrderModel(
      id: order.id,
      orderNumber: order.orderNumber,
      customerId: order.customerId,
      customerName: order.customerName,
      date: order.date,
      shipmentDate: order.shipmentDate,
      items: order.items,
      notes: order.notes,
      isPendingSync: order.isPendingSync,
      status: order.status,
      convertedInvoiceNumber: order.convertedInvoiceNumber,
      zohoOrderId: order.zohoOrderId,
      locationId: order.locationId,
      listedTotal: order.listedTotal,
      orderStatus: order.orderStatus,
      invoicedStatus: order.invoicedStatus,
      referenceNumber: order.referenceNumber,
    );
  }
}
