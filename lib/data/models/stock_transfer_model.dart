import '../../domain/models/stock_transfer.dart';
import 'item_model.dart';

/// Data transfer object representing a [StockTransferLine].
class StockTransferLineModel extends StockTransferLine {
  /// Creates a new [StockTransferLineModel] instance.
  const StockTransferLineModel({required super.item, required super.quantity});

  /// Factory constructor to parse local/remote JSON maps into a [StockTransferLineModel].
  factory StockTransferLineModel.fromJson(Map<String, dynamic> json) {
    return StockTransferLineModel(
      item: ItemModel.fromJson(json['item'] ?? json),
      quantity: json['quantity'] ?? 0,
    );
  }

  /// Converts this [StockTransferLineModel] into a Zoho Transfer Order line-item
  /// compatible JSON map, plus enough local shape to round-trip via [fromJson].
  ///
  /// NOTE: `quantity_transfer` is the Zoho Books Transfer Orders line-item key
  /// for the quantity moved. Verify against the live API — isolated here so a
  /// rename is a one-line fix.
  Map<String, dynamic> toJson() {
    return {
      'item_id': item.id,
      'name': item.name,
      'quantity_transfer': quantity,
      'quantity': quantity,
      'item': ItemModel.fromDomain(item).toJson(),
    };
  }

  /// Translates a base domain [StockTransferLine] entity into its DTO representation.
  factory StockTransferLineModel.fromDomain(StockTransferLine line) {
    return StockTransferLineModel(item: line.item, quantity: line.quantity);
  }
}

/// Data transfer object representing a [StockTransfer].
///
/// `toJson` doubles as the Zoho Transfer Order sync payload (Issue to Van /
/// Stock Unloading) alongside the local-only bookkeeping fields.
class StockTransferModel extends StockTransfer {
  /// Creates a new [StockTransferModel] instance.
  const StockTransferModel({
    required super.id,
    required super.transferNumber,
    required super.date,
    required super.direction,
    required super.fromLocationId,
    required super.toLocationId,
    required super.lines,
    super.notes,
    super.isPendingSync,
    super.zohoTransferId,
    super.locationId,
  });

  /// Factory constructor to parse local database JSON maps into a [StockTransferModel].
  factory StockTransferModel.fromJson(Map<String, dynamic> json) {
    return StockTransferModel(
      id: json['transfer_order_id'] ?? json['id'] ?? '',
      transferNumber:
          json['transfer_order_number'] ?? json['transferNumber'] ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'])
          : DateTime.now(),
      direction: _directionFromString(json['direction']),
      fromLocationId:
          json['from_location_id'] ?? json['fromLocationId'] ?? '',
      toLocationId: json['to_location_id'] ?? json['toLocationId'] ?? '',
      lines:
          (json['line_items'] as List?)
              ?.map((line) => StockTransferLineModel.fromJson(line))
              .toList() ??
          [],
      notes: json['notes'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
      zohoTransferId: json['zoho_transfer_id'],
      locationId: json['location_id'],
    );
  }

  /// Parses a stored direction string into a [StockTransferDirection], defaulting to load.
  static StockTransferDirection _directionFromString(dynamic value) {
    return value == 'unload'
        ? StockTransferDirection.unload
        : StockTransferDirection.load;
  }

  /// Converts this [StockTransferModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transfer_order_id': id,
      'transfer_order_number': transferNumber,
      'date': date.toIso8601String().split('T')[0],
      'direction': direction == StockTransferDirection.unload
          ? 'unload'
          : 'load',
      'from_location_id': fromLocationId,
      'to_location_id': toLocationId,
      'line_items': lines
          .map((line) => StockTransferLineModel.fromDomain(line).toJson())
          .toList(),
      'notes': notes,
      'isPendingSync': isPendingSync,
      'zoho_transfer_id': zohoTransferId,
      'location_id': locationId,
    };
  }

  /// Translates a base domain [StockTransfer] entity into its [StockTransferModel] representation.
  factory StockTransferModel.fromDomain(StockTransfer transfer) {
    return StockTransferModel(
      id: transfer.id,
      transferNumber: transfer.transferNumber,
      date: transfer.date,
      direction: transfer.direction,
      fromLocationId: transfer.fromLocationId,
      toLocationId: transfer.toLocationId,
      lines: transfer.lines,
      notes: transfer.notes,
      isPendingSync: transfer.isPendingSync,
      zohoTransferId: transfer.zohoTransferId,
      locationId: transfer.locationId,
    );
  }
}
