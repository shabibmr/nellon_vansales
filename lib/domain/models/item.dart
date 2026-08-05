import 'package:equatable/equatable.dart';

import 'unit_conversion.dart';

/// Represents an inventory item or product stocked in the delivery van.
///
/// Tracks general product details (name, sku, description), pricing/rate structure,
/// real-time stock levels in the van, and default tax configurations for billing.
class Item extends Equatable {
  /// Unique product identifier (Zoho item_id).
  final String id;

  /// The public display name of the item.
  final String name;

  /// Stock Keeping Unit (SKU) code of the product.
  final String sku;

  /// Standard unit sale price (excluding tax), per base unit ([uom]).
  final double rate;

  /// Current physical quantity available in the van's inventory, in base units.
  final double stock;

  /// Brief product description or details.
  final String description;

  /// Zoho tax_id for this item (e.g. Standard Rate). Empty when unknown.
  ///
  /// Required on invoice/order/credit-note line posts — UAE orgs apply EXEMPT
  /// when lines omit tax_id even if tax_percentage is present.
  final String taxId;

  /// Name of the tax applied to this item (e.g. "Standard Rate").
  final String taxName;

  /// The tax rate percentage (e.g., 5.0 for 5% tax).
  final double taxPercentage;

  /// Base unit of measure from Zoho (e.g. "pcs", "kg", "box"). Empty when unknown.
  final String uom;

  /// Alternate-unit conversions from Zoho (empty until enriched via item detail).
  final List<UnitConversion> unitConversions;

  /// Creates a new [Item] inventory record.
  const Item({
    required this.id,
    required this.name,
    required this.sku,
    required this.rate,
    required this.stock,
    required this.description,
    required this.taxName,
    required this.taxPercentage,
    this.taxId = '',
    this.uom = '',
    this.unitConversions = const [],
  });

  /// The conversion entry for [unitName], or null when it is the base unit
  /// (or unknown).
  UnitConversion? conversionFor(String unitName) {
    for (final c in unitConversions) {
      if (c.targetUnit == unitName) return c;
    }
    return null;
  }

  /// Base-unit multiplier for [unitName] (1.0 for the base unit).
  double conversionRateFor(String unitName) =>
      conversionFor(unitName)?.conversionRate ?? 1.0;

  /// Effective sale rate when selling in [unitName]:
  /// base [rate] × conversion rate. Zoho stores no per-unit price.
  double rateFor(String unitName) => rate * conversionRateFor(unitName);

  /// Creates a copy of this [Item] with replaced values for specific fields.
  Item copyWith({
    String? id,
    String? name,
    String? sku,
    double? rate,
    double? stock,
    String? description,
    String? taxId,
    String? taxName,
    double? taxPercentage,
    String? uom,
    List<UnitConversion>? unitConversions,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      rate: rate ?? this.rate,
      stock: stock ?? this.stock,
      description: description ?? this.description,
      taxId: taxId ?? this.taxId,
      taxName: taxName ?? this.taxName,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      uom: uom ?? this.uom,
      unitConversions: unitConversions ?? this.unitConversions,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    sku,
    rate,
    stock,
    description,
    taxId,
    taxName,
    taxPercentage,
    uom,
    unitConversions,
  ];
}
