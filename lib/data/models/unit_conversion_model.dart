import '../../domain/models/unit_conversion.dart';

/// Data transfer object for a Zoho `unit_conversions` entry.
///
/// Keys mirror the Zoho item-detail response verbatim so the Hive round-trip
/// stores the same shape the API returned.
class UnitConversionModel extends UnitConversion {
  /// Creates a new [UnitConversionModel] instance.
  const UnitConversionModel({
    required super.unitConversionId,
    required super.targetUnitId,
    required super.targetUnit,
    required super.conversionRate,
    super.quantityDecimalPlaces = 2,
  });

  /// Parses a Zoho `unit_conversions` entry (or the local cache of one).
  factory UnitConversionModel.fromJson(Map<String, dynamic> json) {
    return UnitConversionModel(
      unitConversionId: (json['unit_conversion_id'] ?? '').toString(),
      targetUnitId: (json['target_unit_id'] ?? '').toString(),
      targetUnit: (json['target_unit'] ?? '').toString(),
      conversionRate: ((json['conversion_rate'] ?? 1) as num).toDouble(),
      quantityDecimalPlaces: ((json['quantity_decimal_place'] ?? 2) as num)
          .toInt(),
    );
  }

  /// Converts to the Zoho-shaped JSON map.
  Map<String, dynamic> toJson() {
    return {
      'unit_conversion_id': unitConversionId,
      'target_unit_id': targetUnitId,
      'target_unit': targetUnit,
      'conversion_rate': conversionRate,
      'quantity_decimal_place': quantityDecimalPlaces,
    };
  }

  /// Maps a domain [UnitConversion] into its model representation.
  factory UnitConversionModel.fromDomain(UnitConversion c) {
    return UnitConversionModel(
      unitConversionId: c.unitConversionId,
      targetUnitId: c.targetUnitId,
      targetUnit: c.targetUnit,
      conversionRate: c.conversionRate,
      quantityDecimalPlaces: c.quantityDecimalPlaces,
    );
  }
}
