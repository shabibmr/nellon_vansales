import 'package:equatable/equatable.dart';
import 'item.dart';

/// Represents a single line item entry in a sales order.
///
/// Encapsulates the product, the quantity ordered, the standard rate, and computed tax totals.
class OrderLineItem extends Equatable {
  /// The inventory product/item referenced.
  final Item item;

  /// Quantity of items ordered.
  final int quantity;

  /// Ordered rate per unit item.
  final double rate;

  /// Percentage of tax applied (e.g. 5.0).
  final double taxPercentage;

  /// Line item discount.
  final double discount;

  /// Creates a new [OrderLineItem].
  const OrderLineItem({
    required this.item,
    required this.quantity,
    required this.rate,
    required this.taxPercentage,
    this.discount = 0.0,
  });

  /// Computes the cost excluding tax.
  double get subTotal => rate * quantity;

  /// Computes the specific tax portion amount.
  double get taxAmount => subTotal * (taxPercentage / 100);

  /// Computes the gross line total including tax and subtracting discount.
  double get total => subTotal + taxAmount - discount;

  /// Creates a copy of this [OrderLineItem] with replaced values for specific fields.
  OrderLineItem copyWith({
    Item? item,
    int? quantity,
    double? rate,
    double? taxPercentage,
    double? discount,
  }) {
    return OrderLineItem(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
      rate: rate ?? this.rate,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      discount: discount ?? this.discount,
    );
  }

  @override
  List<Object?> get props => [item, quantity, rate, taxPercentage, discount];
}

/// Lifecycle status of a sales order, mirroring Zoho Books.
///
/// [open] — created, not yet invoiced. [invoiced] — converted to an invoice.
enum SalesOrderStatus { open, invoiced }

/// Represents a Sales Order created during route delivery.
///
/// Contains details of the customer, shipment details, order lines,
/// and computed totals (subtotal, tax sum, grand total).
class SalesOrder extends Equatable {
  /// Unique identifier of the sales order.
  final String id;

  /// Human-readable billing voucher reference code.
  final String orderNumber;

  /// The customer ID.
  final String customerId;

  /// Display name of the customer.
  final String customerName;

  /// The date when the order was issued.
  final DateTime date;

  /// The shipment date.
  final DateTime shipmentDate;

  /// Collection of ordered product items.
  final List<OrderLineItem> items;

  /// Customer notes or delivery remarks.
  final String notes;

  /// Flag indicating if the order is pending synchronization with Zoho Books.
  final bool isPendingSync;

  /// Lifecycle status; flips to [SalesOrderStatus.invoiced] once converted.
  final SalesOrderStatus status;

  /// Number of the invoice this order was converted into, if any.
  final String? convertedInvoiceNumber;

  /// The permanent Zoho `salesorder_id`, populated once the order syncs.
  final String? zohoOrderId;

  /// Creates a new [SalesOrder].
  const SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.shipmentDate,
    required this.items,
    required this.notes,
    this.isPendingSync = false,
    this.status = SalesOrderStatus.open,
    this.convertedInvoiceNumber,
    this.zohoOrderId,
  });

  /// Whether this order has already been converted into an invoice.
  bool get isConverted => status == SalesOrderStatus.invoiced;

  /// Computes sum of all sub-totals (excluding taxes).
  double get subTotal => items.fold(0.0, (sum, item) => sum + item.subTotal);

  /// Computes total accumulated tax on this order.
  double get taxTotal => items.fold(0.0, (sum, item) => sum + item.taxAmount);

  /// Computes total line-item discount on this order.
  double get discountTotal =>
      items.fold(0.0, (sum, item) => sum + item.discount);

  /// Computes the unrounded grand total.
  double get rawTotal => items.fold(0.0, (sum, item) => sum + item.total);

  /// Computes the final grand total billed, rounded to the nearest integer.
  double get total => rawTotal.roundToDouble();

  /// Computes the round off adjustment.
  double get roundOff => total - rawTotal;

  /// Creates a copy of this [SalesOrder] with replaced values for specific fields.
  SalesOrder copyWith({
    String? id,
    String? orderNumber,
    String? customerId,
    String? customerName,
    DateTime? date,
    DateTime? shipmentDate,
    List<OrderLineItem>? items,
    String? notes,
    bool? isPendingSync,
    SalesOrderStatus? status,
    String? convertedInvoiceNumber,
    String? zohoOrderId,
  }) {
    return SalesOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      shipmentDate: shipmentDate ?? this.shipmentDate,
      items: items ?? this.items,
      notes: notes ?? this.notes,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      status: status ?? this.status,
      convertedInvoiceNumber:
          convertedInvoiceNumber ?? this.convertedInvoiceNumber,
      zohoOrderId: zohoOrderId ?? this.zohoOrderId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    orderNumber,
    customerId,
    customerName,
    date,
    shipmentDate,
    items,
    notes,
    isPendingSync,
    status,
    convertedInvoiceNumber,
    zohoOrderId,
  ];
}
