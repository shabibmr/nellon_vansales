import 'package:equatable/equatable.dart';
import 'item.dart';

/// Represents a single line item entry in a sales invoice.
///
/// Encapsulates the product, the quantity billed, the standard rate, and computed tax totals.
class InvoiceLineItem extends Equatable {
  /// The inventory product/item referenced.
  final Item item;

  /// Quantity of items purchased.
  final int quantity;

  /// Invoiced rate per unit item.
  final double rate;

  /// Percentage of tax applied (e.g. 5.0).
  final double taxPercentage;

  /// Line item discount.
  final double discount;

  /// Creates a new [InvoiceLineItem].
  const InvoiceLineItem({
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

  /// Creates a copy of this [InvoiceLineItem] with replaced values for specific fields.
  InvoiceLineItem copyWith({
    Item? item,
    int? quantity,
    double? rate,
    double? taxPercentage,
    double? discount,
  }) {
    return InvoiceLineItem(
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

/// Represents a Sales Invoice created during route delivery.
///
/// Contains details of the customer billed, payment terms (dates), invoice lines,
/// and computed totals (subtotal, tax sum, grand total).
class SalesInvoice extends Equatable {
  /// Unique identifier of the sales invoice.
  final String id;

  /// Human-readable billing voucher reference code.
  final String invoiceNumber;

  /// The customer ID.
  final String customerId;

  /// Display name of the customer.
  final String customerName;

  /// The date when the invoice was issued.
  final DateTime date;

  /// The payment deadline date.
  final DateTime dueDate;

  /// Collection of invoiced product items.
  final List<InvoiceLineItem> items;

  /// Customer notes or delivery remarks.
  final String notes;

  /// Flag indicating if the invoice is pending synchronization with Zoho Books.
  final bool isPendingSync;

  /// The Zoho Location ID of the salesperson/van that created this invoice.
  final String? locationId;

  /// Creates a new [SalesInvoice].
  const SalesInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.dueDate,
    required this.items,
    required this.notes,
    this.isPendingSync = false,
    this.locationId,
  });

  /// Computes sum of all sub-totals (excluding taxes).
  double get subTotal => items.fold(0.0, (sum, item) => sum + item.subTotal);

  /// Computes total accumulated tax on this invoice.
  double get taxTotal => items.fold(0.0, (sum, item) => sum + item.taxAmount);

  /// Computes total line-item discount on this invoice.
  double get discountTotal =>
      items.fold(0.0, (sum, item) => sum + item.discount);

  /// Computes the unrounded grand total.
  double get rawTotal => items.fold(0.0, (sum, item) => sum + item.total);

  /// Computes the final grand total billed, rounded to the nearest integer.
  double get total => rawTotal.roundToDouble();

  /// Computes the round off adjustment.
  double get roundOff => total - rawTotal;

  /// Creates a copy of this [SalesInvoice] with replaced values for specific fields.
  SalesInvoice copyWith({
    String? id,
    String? invoiceNumber,
    String? customerId,
    String? customerName,
    DateTime? date,
    DateTime? dueDate,
    List<InvoiceLineItem>? items,
    String? notes,
    bool? isPendingSync,
    String? locationId,
  }) {
    return SalesInvoice(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      items: items ?? this.items,
      notes: notes ?? this.notes,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      locationId: locationId ?? this.locationId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    invoiceNumber,
    customerId,
    customerName,
    date,
    dueDate,
    items,
    notes,
    isPendingSync,
    locationId,
  ];
}
