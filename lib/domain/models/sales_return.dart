import 'package:equatable/equatable.dart';
import 'sales_invoice.dart';
import '../utils/money_math.dart';

/// Represents a single returned line item in a customer sales return/credit note.
///
/// Wraps the original invoiced line item and specifies the quantity being returned by the customer.
class SalesReturnLineItem extends Equatable {
  /// The original invoiced line item reference.
  final InvoiceLineItem invoiceLineItem;

  /// Quantity of items returned by the customer, in the selected return
  /// unit ([displayUom]).
  final double returnedQuantity;

  /// The ID of the sales invoice from which the item is returned.
  final String? invoiceId;

  /// The number of the sales invoice from which the item is returned.
  final String? invoiceNumber;

  /// Unit the return is expressed in. Empty = same unit the item was sold in.
  final String uom;

  /// Zoho `unit_conversion_id` for [uom] when it is an alternate unit; empty
  /// for the item's base unit (or when inheriting the sold unit).
  final String unitConversionId;

  /// Creates a new [SalesReturnLineItem].
  const SalesReturnLineItem({
    required this.invoiceLineItem,
    required this.returnedQuantity,
    this.invoiceId,
    this.invoiceNumber,
    this.uom = '',
    this.unitConversionId = '',
  });

  /// Effective UOM of the returned quantity — line override, else the unit
  /// the item was originally sold in.
  String get displayUom => uom.isNotEmpty ? uom : invoiceLineItem.displayUom;

  /// Base-unit multiplier of the unit the item was originally sold in.
  double get _soldConversionRate =>
      invoiceLineItem.item.conversionRateFor(invoiceLineItem.displayUom);

  /// Base-unit multiplier of the unit this return is expressed in.
  double get _returnConversionRate =>
      invoiceLineItem.item.conversionRateFor(displayUom);

  /// Rate per returned unit, derived from the price actually charged on the
  /// invoice: invoiced rate ÷ sold-unit rate × return-unit rate. Not rounded —
  /// rates can carry more than 2 decimals (e.g. 4.875/kg); only line totals
  /// are money-rounded.
  double get rate {
    if (_soldConversionRate <= 0) return invoiceLineItem.rate;
    if (_returnConversionRate == _soldConversionRate) {
      return invoiceLineItem.rate;
    }
    return invoiceLineItem.rate / _soldConversionRate * _returnConversionRate;
  }

  /// The returned quantity converted into the item's base unit.
  double get returnedQuantityInBase =>
      returnedQuantity * _returnConversionRate;

  /// Computes the cost excluding tax for the quantity returned.
  double get subTotal => roundMoney(rate * returnedQuantity);

  /// Computes the tax portion applicable to the returned quantity, using the
  /// original invoiced line's tax rate.
  double get taxAmount =>
      roundMoney(subTotal * (invoiceLineItem.taxPercentage / 100));

  /// Prorates the original line's discount to the quantity being returned, so
  /// a partial return of a discounted line correctly reduces the credit.
  ///
  /// e.g. a 10-unit line discounted by 5.00 total, returning 2 units, credits
  /// back only 1.00 (2/10) of that discount rather than the full 5.00.
  double get discountAmount {
    if (invoiceLineItem.quantity <= 0) return 0.0;
    // Prorate in base units so a return in a different unit than sold still
    // credits the right share of the original discount.
    final soldBaseQty = invoiceLineItem.quantity * _soldConversionRate;
    if (soldBaseQty <= 0) return 0.0;
    final perBaseUnitDiscount = invoiceLineItem.discount / soldBaseQty;
    return roundMoney(perBaseUnitDiscount * returnedQuantityInBase);
  }

  /// Computes the total return credit value, aligned with [InvoiceLineItem]'s
  /// subtotal → tax → discount calculation so returns reconcile against the
  /// originating invoice.
  double get total => roundMoney(subTotal + taxAmount - discountAmount);

  /// Creates a copy of this [SalesReturnLineItem] with replaced values for specific fields.
  SalesReturnLineItem copyWith({
    InvoiceLineItem? invoiceLineItem,
    double? returnedQuantity,
    String? invoiceId,
    String? invoiceNumber,
    String? uom,
    String? unitConversionId,
  }) {
    return SalesReturnLineItem(
      invoiceLineItem: invoiceLineItem ?? this.invoiceLineItem,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      uom: uom ?? this.uom,
      unitConversionId: unitConversionId ?? this.unitConversionId,
    );
  }

  @override
  List<Object?> get props => [
    invoiceLineItem,
    returnedQuantity,
    invoiceId,
    invoiceNumber,
    uom,
    unitConversionId,
  ];
}

/// Represents a Sales Return (Credit Note) voucher created locally.
///
/// Logged when a customer returns goods on the route due to damage, incorrect item, or surplus.
class SalesReturn extends Equatable {
  /// Unique identifier of the sales return record.
  final String id;

  /// Human-readable credit note reference number.
  final String creditNoteNumber;

  /// The customer ID.
  final String customerId;

  /// Display name of the customer.
  final String customerName;

  /// Date the return was processed.
  final DateTime date;

  /// Collection of returned line items.
  final List<SalesReturnLineItem> items;

  /// Description/reason for the return.
  final String reason;

  /// Flag indicating if the return is pending synchronization with Zoho Books.
  final bool isPendingSync;

  /// The Zoho Location ID of the salesperson/van that created this return.
  final String? locationId;

  /// Creates a new [SalesReturn] record.
  const SalesReturn({
    required this.id,
    required this.creditNoteNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.items,
    required this.reason,
    this.isPendingSync = false,
    this.locationId,
  });

  /// Computes the final grand total return value.
  double get total =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.total));

  /// Creates a copy of this [SalesReturn] with replaced values for specific fields.
  SalesReturn copyWith({
    String? id,
    String? creditNoteNumber,
    String? customerId,
    String? customerName,
    DateTime? date,
    List<SalesReturnLineItem>? items,
    String? reason,
    bool? isPendingSync,
    String? locationId,
  }) {
    return SalesReturn(
      id: id ?? this.id,
      creditNoteNumber: creditNoteNumber ?? this.creditNoteNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      items: items ?? this.items,
      reason: reason ?? this.reason,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      locationId: locationId ?? this.locationId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    creditNoteNumber,
    customerId,
    customerName,
    date,
    items,
    reason,
    isPendingSync,
    locationId,
  ];
}
