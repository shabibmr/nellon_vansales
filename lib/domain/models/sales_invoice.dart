import 'package:equatable/equatable.dart';
import 'item.dart';
import '../utils/money_math.dart';

/// Represents a single line item entry in a sales invoice.
///
/// Encapsulates the product, the quantity billed, the standard rate, and computed tax totals.
class InvoiceLineItem extends Equatable {
  /// The inventory product/item referenced.
  final Item item;

  /// Quantity of items purchased, expressed in the selected unit ([displayUom]).
  final double quantity;

  /// Invoiced rate per selected unit.
  final double rate;

  /// Percentage of tax applied (e.g. 5.0).
  final double taxPercentage;

  /// Line item discount.
  final double discount;

  /// Unit of measure for this line (defaults to [Item.uom] when empty).
  final String uom;

  /// Zoho `unit_conversion_id` when [uom] is an alternate unit; empty for
  /// the item's base unit.
  final String unitConversionId;

  /// Creates a new [InvoiceLineItem].
  const InvoiceLineItem({
    required this.item,
    required this.quantity,
    required this.rate,
    required this.taxPercentage,
    this.discount = 0.0,
    this.uom = '',
    this.unitConversionId = '',
  });

  /// Effective UOM for display/sync — line override, else item master.
  String get displayUom => uom.isNotEmpty ? uom : item.uom;

  /// The quantity converted into the item's base unit — stock math always
  /// operates in base units (e.g. 2 × "25 Kg Bag" → 50 kg).
  double get quantityInBase => quantity * item.conversionRateFor(displayUom);

  /// Computes the cost excluding tax.
  double get subTotal => roundMoney(rate * quantity);

  /// Computes the specific tax portion amount.
  double get taxAmount => roundMoney(subTotal * (taxPercentage / 100));

  /// Computes the gross line total including tax and subtracting discount.
  double get total => roundMoney(subTotal + taxAmount - discount);

  /// Creates a copy of this [InvoiceLineItem] with replaced values for specific fields.
  InvoiceLineItem copyWith({
    Item? item,
    double? quantity,
    double? rate,
    double? taxPercentage,
    double? discount,
    String? uom,
    String? unitConversionId,
  }) {
    return InvoiceLineItem(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
      rate: rate ?? this.rate,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      discount: discount ?? this.discount,
      uom: uom ?? this.uom,
      unitConversionId: unitConversionId ?? this.unitConversionId,
    );
  }

  @override
  List<Object?> get props =>
      [item, quantity, rate, taxPercentage, discount, uom, unitConversionId];
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

  /// The permanent Zoho `invoice_id`, populated once the invoice syncs.
  final String? zohoInvoiceId;

  /// The Zoho Location ID of the salesperson/van that created this invoice.
  final String? locationId;

  /// Zoho list/detail payment status (e.g. unpaid, paid, overdue). Empty when unknown.
  final String status;

  /// Grand total from Zoho list headers when [items] are not loaded.
  ///
  /// Prefer line-derived totals when [items] is non-empty.
  final double? listedTotal;

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
    this.zohoInvoiceId,
    this.locationId,
    this.status = '',
    this.listedTotal,
  });

  /// Computes sum of all sub-totals (excluding taxes).
  double get subTotal =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.subTotal));

  /// Computes total accumulated tax on this invoice.
  double get taxTotal =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.taxAmount));

  /// Computes total line-item discount on this invoice.
  double get discountTotal =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.discount));

  /// Computes the unrounded grand total from line items.
  double get rawTotal =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.total));

  /// Final grand total: line-derived when items exist, else [listedTotal].
  double get total {
    if (items.isNotEmpty) return rawTotal.roundToDouble();
    if (listedTotal != null) return listedTotal!.roundToDouble();
    return 0.0;
  }

  /// Computes the round off adjustment (meaningful when line items exist).
  double get roundOff {
    if (items.isEmpty) return 0.0;
    return roundMoney(total - rawTotal);
  }

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
    String? zohoInvoiceId,
    String? locationId,
    String? status,
    double? listedTotal,
    bool clearListedTotal = false,
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
      zohoInvoiceId: zohoInvoiceId ?? this.zohoInvoiceId,
      locationId: locationId ?? this.locationId,
      status: status ?? this.status,
      listedTotal: clearListedTotal ? null : (listedTotal ?? this.listedTotal),
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
    zohoInvoiceId,
    locationId,
    status,
    listedTotal,
  ];
}
