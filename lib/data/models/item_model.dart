import '../../domain/models/item.dart';
import 'unit_conversion_model.dart';

/// Parses a JSON value that may be a [num] or a numeric [String] (Zoho
/// sometimes returns numeric fields as strings).
double _parseNum(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

/// Data transfer object representing stocked inventory [Item]s.
///
/// Bridges the UI representation of stocked goods with Zoho Books Item API payloads.
class ItemModel extends Item {
  /// Creates a new [ItemModel] instance.
  const ItemModel({
    required super.id,
    required super.name,
    required super.sku,
    required super.rate,
    required super.stock,
    required super.description,
    required super.taxName,
    required super.taxPercentage,
    super.taxId = '',
    super.uom = '',
    super.unitConversions = const [],
  });

  /// Factory constructor to parse local/remote JSON into an [ItemModel].
  ///
  /// Maps Zoho API keys (`item_id`, `stock_on_hand`, `tax_id`, `tax_percentage`,
  /// `unit`) with empty/zero defaults when tax is absent (do not invent
  /// "VAT 5%" — this org uses "Standard Rate" / tax_id).
  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: ((json['item_id'] ?? json['id']) as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sku: (json['sku'] as String?) ?? '',
      rate: _parseNum(json['rate'] ?? json['price']),
      stock: _parseNum(json['stock_on_hand'] ?? json['stock']),
      description: (json['description'] as String?) ?? '',
      taxId: ((json['tax_id'] ?? json['taxId']) as String?) ?? '',
      taxName: ((json['tax_name'] ?? json['taxName']) as String?) ?? '',
      taxPercentage: _parseNum(
        json['tax_percentage'] ?? json['taxPercentage'],
      ),
      // Zoho Books/Inventory use `unit`; local cache may store `uom`.
      uom: (json['unit'] ?? json['uom'] ?? '').toString(),
      // Only present after unit-conversion enrichment (item detail fetch).
      unitConversions: (json['unit_conversions'] as List<dynamic>? ?? const [])
          .map((c) => UnitConversionModel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Converts this [ItemModel] into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_id': id,
      'name': name,
      'sku': sku,
      'rate': rate,
      'stock': stock,
      'stock_on_hand': stock,
      'description': description,
      'tax_id': taxId,
      'tax_name': taxName,
      'tax_percentage': taxPercentage,
      'unit': uom,
      'uom': uom,
      'unit_conversions': unitConversions
          .map((c) => UnitConversionModel.fromDomain(c).toJson())
          .toList(),
    };
  }

  /// Maps a base domain [Item] entity into its [ItemModel] representation.
  factory ItemModel.fromDomain(Item item) {
    return ItemModel(
      id: item.id,
      name: item.name,
      sku: item.sku,
      rate: item.rate,
      stock: item.stock,
      description: item.description,
      taxId: item.taxId,
      taxName: item.taxName,
      taxPercentage: item.taxPercentage,
      uom: item.uom,
      unitConversions: item.unitConversions,
    );
  }
}
