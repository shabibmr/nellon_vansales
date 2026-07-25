import 'package:equatable/equatable.dart';
import 'item.dart';

/// Direction of a physical stock movement between Zoho Books locations.
///
/// [load] — from the default warehouse into the van's current location
/// (Issue to Van). [unload] — from the van's current location back to the
/// default warehouse (Stock Unloading / end-of-trip return).
enum StockTransferDirection { load, unload }

/// Represents a single transferred product line.
///
/// Unlike invoice/order lines, a transfer line has no rate or tax — it only
/// tracks the physical quantity moved between locations.
class StockTransferLine extends Equatable {
  /// The inventory product/item referenced.
  final Item item;

  /// Quantity of this item actually transferred, in the item's **base unit**
  /// (the payload and local stock math always operate in base units).
  final double quantity;

  /// Unit the quantity was entered in (display only; defaults to base unit).
  final String uom;

  /// Base-unit multiplier of [uom] (1.0 when entered in the base unit).
  final double conversionRate;

  /// Creates a new [StockTransferLine].
  const StockTransferLine({
    required this.item,
    required this.quantity,
    this.uom = '',
    this.conversionRate = 1.0,
  });

  /// The quantity as entered, expressed in [uom]
  /// (e.g. base 50 kg entered as "2 × 25 Kg Bag" → 2).
  double get enteredQuantity =>
      conversionRate > 0 ? quantity / conversionRate : quantity;

  /// Creates a copy of this [StockTransferLine] with replaced values for specific fields.
  StockTransferLine copyWith({
    Item? item,
    double? quantity,
    String? uom,
    double? conversionRate,
  }) {
    return StockTransferLine(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
      uom: uom ?? this.uom,
      conversionRate: conversionRate ?? this.conversionRate,
    );
  }

  @override
  List<Object?> get props => [item, quantity, uom, conversionRate];
}

/// Represents a physical stock transfer between two Zoho Books locations
/// (Issue to Van or Stock Unloading), synced as a Zoho Transfer Order.
class StockTransfer extends Equatable {
  /// Unique identifier of the stock transfer.
  final String id;

  /// Human-readable transfer voucher reference code.
  final String transferNumber;

  /// The date the transfer was issued.
  final DateTime date;

  /// Whether this transfer loads the van (from warehouse) or unloads it (to warehouse).
  final StockTransferDirection direction;

  /// The Zoho Location ID stock is moved out of.
  final String fromLocationId;

  /// The Zoho Location ID stock is moved into.
  final String toLocationId;

  /// Collection of transferred product lines.
  final List<StockTransferLine> lines;

  /// Optional remarks.
  final String notes;

  /// Flag indicating if the transfer is pending synchronization with Zoho Books.
  final bool isPendingSync;

  /// The permanent Zoho `transfer_order_id`, populated once the transfer syncs.
  final String? zohoTransferId;

  /// The Zoho Location ID of the salesperson/van session that created this
  /// transfer — used to scope local history to the active session location.
  final String? locationId;

  /// Creates a new [StockTransfer].
  const StockTransfer({
    required this.id,
    required this.transferNumber,
    required this.date,
    required this.direction,
    required this.fromLocationId,
    required this.toLocationId,
    required this.lines,
    this.notes = '',
    this.isPendingSync = false,
    this.zohoTransferId,
    this.locationId,
  });

  /// Computes the total quantity of items moved across all lines (base units).
  double get totalQuantity =>
      lines.fold(0.0, (sum, line) => sum + line.quantity);

  /// Creates a copy of this [StockTransfer] with replaced values for specific fields.
  StockTransfer copyWith({
    String? id,
    String? transferNumber,
    DateTime? date,
    StockTransferDirection? direction,
    String? fromLocationId,
    String? toLocationId,
    List<StockTransferLine>? lines,
    String? notes,
    bool? isPendingSync,
    String? zohoTransferId,
    String? locationId,
  }) {
    return StockTransfer(
      id: id ?? this.id,
      transferNumber: transferNumber ?? this.transferNumber,
      date: date ?? this.date,
      direction: direction ?? this.direction,
      fromLocationId: fromLocationId ?? this.fromLocationId,
      toLocationId: toLocationId ?? this.toLocationId,
      lines: lines ?? this.lines,
      notes: notes ?? this.notes,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      zohoTransferId: zohoTransferId ?? this.zohoTransferId,
      locationId: locationId ?? this.locationId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    transferNumber,
    date,
    direction,
    fromLocationId,
    toLocationId,
    lines,
    notes,
    isPendingSync,
    zohoTransferId,
    locationId,
  ];
}
