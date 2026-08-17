import '../../domain/models/stock_transfer.dart';
import 'item_model.dart';
import 'json_read.dart';

/// Data transfer object representing a [StockTransferLine].
class StockTransferLineModel extends StockTransferLine {
  /// Creates a new [StockTransferLineModel] instance.
  const StockTransferLineModel({
    required super.item,
    required super.quantity,
    super.uom = '',
    super.conversionRate = 1.0,
  });

  /// Factory constructor to parse local/remote JSON maps into a [StockTransferLineModel].
  factory StockTransferLineModel.fromJson(Map<String, dynamic> json) {
    return StockTransferLineModel(
      item: ItemModel.fromJson(jsonMap(json['item'] ?? json)),
      quantity: jsonDouble(json['quantity']),
      uom: (json['entered_uom'] ?? '').toString(),
      conversionRate: ((json['entered_conversion_rate'] ?? 1) as num)
          .toDouble(),
    );
  }

  /// Converts this [StockTransferLineModel] into a Zoho Transfer Order line-item
  /// compatible JSON map, plus enough local shape to round-trip via [fromJson].
  ///
  /// `quantity`/`quantity_transfer` are always in the item's **base unit**;
  /// `entered_uom`/`entered_conversion_rate` are local-only display keys.
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
      if (uom.isNotEmpty) 'entered_uom': uom,
      if (uom.isNotEmpty) 'entered_conversion_rate': conversionRate,
      'item': ItemModel.fromDomain(item).toJson(),
    };
  }

  /// Translates a base domain [StockTransferLine] entity into its DTO representation.
  factory StockTransferLineModel.fromDomain(StockTransferLine line) {
    return StockTransferLineModel(
      item: line.item,
      quantity: line.quantity,
      uom: line.uom,
      conversionRate: line.conversionRate,
    );
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
    super.status,
  });

  /// Factory constructor to parse local database JSON maps into a [StockTransferModel].
  ///
  /// `id` wins over `transfer_order_id` when both are present: a local
  /// record always carries both (historically equal), but an
  /// `update_stock_transfer` sync payload stamps `transfer_order_id` with
  /// the *real* Zoho id while `id` stays the local record's join key — that
  /// must not be clobbered by the Zoho id on round-trip. A pure remote fetch
  /// has no `id` key at all, so it still falls back to `transfer_order_id`.
  factory StockTransferModel.fromJson(Map<String, dynamic> json) {
    return StockTransferModel(
      id: jsonString(json['id'] ?? json['transfer_order_id']),
      transferNumber:
          jsonString(json['transfer_order_number'] ?? json['transferNumber']),
      date: jsonDate(json['date']),
      direction: _directionFromString(json['direction']),
      fromLocationId:
          jsonString(json['from_location_id'] ?? json['fromLocationId']),
      toLocationId: jsonString(json['to_location_id'] ?? json['toLocationId']),
      lines:
          jsonList(json['line_items'])
              .map((line) => StockTransferLineModel.fromJson(jsonMap(line)))
              .toList(),
      notes: jsonString(json['notes']),
      isPendingSync: jsonBool(json['isPendingSync']),
      zohoTransferId: jsonStringOrNull(json['zoho_transfer_id']),
      locationId: jsonStringOrNull(json['location_id']),
      status: jsonString(json['status'], 'draft'),
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
      'status': status,
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
      status: transfer.status,
    );
  }
}
