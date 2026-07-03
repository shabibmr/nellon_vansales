import 'package:equatable/equatable.dart';

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

  /// Standard unit sale price (excluding tax).
  final double rate;

  /// Current physical quantity available in the van's inventory.
  final int stock;

  /// Brief product description or details.
  final String description;

  /// Name of the tax applied to this item (e.g. VAT 5%).
  final String taxName;

  /// The tax rate percentage (e.g., 5.0 for 5% tax).
  final double taxPercentage;

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
  });

  /// Creates a copy of this [Item] with replaced values for specific fields.
  Item copyWith({
    String? id,
    String? name,
    String? sku,
    double? rate,
    int? stock,
    String? description,
    String? taxName,
    double? taxPercentage,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      rate: rate ?? this.rate,
      stock: stock ?? this.stock,
      description: description ?? this.description,
      taxName: taxName ?? this.taxName,
      taxPercentage: taxPercentage ?? this.taxPercentage,
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
    taxName,
    taxPercentage,
  ];
}
