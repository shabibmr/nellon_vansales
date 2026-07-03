import '../../domain/models/tax.dart';

/// Data transfer object representing a [Tax] configuration.
///
/// Handles JSON mappings for the Zoho Books Tax API endpoints and local caching structures.
class TaxModel extends Tax {
  /// Creates a new [TaxModel] instance.
  const TaxModel({
    required super.id,
    required super.name,
    required super.percentage,
    required super.type,
    super.isDefault,
  });

  /// Factory constructor to parse local/remote JSON maps into a [TaxModel].
  ///
  /// Mappes keys (`tax_id`, `tax_percentage`, `is_default_tax`) to their parent domains.
  factory TaxModel.fromJson(Map<String, dynamic> json) {
    return TaxModel(
      id: json['tax_id'] ?? json['id'] ?? '',
      name: json['tax_name'] ?? json['name'] ?? '',
      percentage: (json['tax_percentage'] ?? json['percentage'] ?? 0.0)
          .toDouble(),
      type: json['tax_type'] ?? json['type'] ?? 'tax',
      isDefault: json['is_default_tax'] ?? json['isDefault'] ?? false,
    );
  }

  /// Converts this [TaxModel] into a serialization compatible JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tax_id': id,
      'name': name,
      'tax_name': name,
      'percentage': percentage,
      'tax_percentage': percentage,
      'tax_type': type,
      'is_default_tax': isDefault,
    };
  }

  /// Translates a base domain [Tax] entity into a serializable [TaxModel].
  factory TaxModel.fromDomain(Tax t) {
    return TaxModel(
      id: t.id,
      name: t.name,
      percentage: t.percentage,
      type: t.type,
      isDefault: t.isDefault,
    );
  }
}
