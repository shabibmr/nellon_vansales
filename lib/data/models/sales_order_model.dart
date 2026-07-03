import '../../domain/models/sales_order.dart';
import 'item_model.dart';

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
  });

  /// Factory constructor to parse local/remote JSON maps into an [OrderLineItemModel].
  factory OrderLineItemModel.fromJson(Map<String, dynamic> json) {
    return OrderLineItemModel(
      item: ItemModel.fromJson(json['item'] ?? json),
      quantity: json['quantity'] ?? 1,
      rate: (json['rate'] ?? 0.0).toDouble(),
      taxPercentage: (json['tax_percentage'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? 0.0).toDouble(),
    );
  }

  /// Converts this [OrderLineItemModel] into a serialization compatible JSON map.
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

  /// Translates a base domain [OrderLineItem] entity into its [OrderLineItemModel] DTO representation.
  factory OrderLineItemModel.fromDomain(OrderLineItem lineItem) {
    return OrderLineItemModel(
      item: lineItem.item,
      quantity: lineItem.quantity,
      rate: lineItem.rate,
      taxPercentage: lineItem.taxPercentage,
      discount: lineItem.discount,
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
  });

  /// Factory constructor to parse local database JSON maps into a [SalesOrderModel].
  factory SalesOrderModel.fromJson(Map<String, dynamic> json) {
    return SalesOrderModel(
      id: json['salesorder_id'] ?? json['id'] ?? '',
      orderNumber: json['salesorder_number'] ?? json['orderNumber'] ?? '',
      customerId: json['customer_id'] ?? json['customerId'] ?? '',
      customerName: json['customer_name'] ?? json['customerName'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      shipmentDate: json['shipment_date'] != null ? DateTime.parse(json['shipment_date']) : DateTime.now(),
      items: (json['line_items'] as List?)
              ?.map((item) => OrderLineItemModel.fromJson(item))
              .toList() ??
          [],
      notes: json['notes'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
      status: _statusFromString(json['status']),
      convertedInvoiceNumber: json['converted_invoice_number'],
      zohoOrderId: json['zoho_order_id'],
    );
  }

  /// Parses a stored status string into a [SalesOrderStatus], defaulting to open.
  static SalesOrderStatus _statusFromString(dynamic value) {
    return value == 'invoiced' ? SalesOrderStatus.invoiced : SalesOrderStatus.open;
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
      'converted_invoice_number': convertedInvoiceNumber,
      'zoho_order_id': zohoOrderId,
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
    );
  }
}
