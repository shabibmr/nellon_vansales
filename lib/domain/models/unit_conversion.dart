import 'package:equatable/equatable.dart';

/// A single alternate-unit conversion for an item, mirroring Zoho Books'
/// `unit_conversions` entries (e.g. base unit "kg" → "25 Kg Bag" at rate 25).
///
/// Zoho stores no per-unit price: the effective rate of a target unit is
/// always `item.rate * conversionRate`.
class UnitConversion extends Equatable {
  /// Zoho `unit_conversion_id` — sent back on transaction line items.
  final String unitConversionId;

  /// Zoho `target_unit_id` of the alternate unit.
  final String targetUnitId;

  /// Display name of the alternate unit (e.g. "25 Kg Bag").
  final String targetUnit;

  /// How many base units one target unit contains (e.g. 25.0).
  final double conversionRate;

  /// Number of decimal places allowed for quantities in this unit.
  final int quantityDecimalPlaces;

  const UnitConversion({
    required this.unitConversionId,
    required this.targetUnitId,
    required this.targetUnit,
    required this.conversionRate,
    this.quantityDecimalPlaces = 2,
  });

  @override
  List<Object?> get props => [
    unitConversionId,
    targetUnitId,
    targetUnit,
    conversionRate,
    quantityDecimalPlaces,
  ];
}
