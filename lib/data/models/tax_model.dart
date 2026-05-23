import '../../domain/models/tax.dart';

class TaxModel extends Tax {
  const TaxModel({
    required super.id,
    required super.name,
    required super.percentage,
    required super.type,
    super.isDefault,
  });

  factory TaxModel.fromJson(Map<String, dynamic> json) {
    return TaxModel(
      id: json['tax_id'] ?? json['id'] ?? '',
      name: json['tax_name'] ?? json['name'] ?? '',
      percentage: (json['tax_percentage'] ?? json['percentage'] ?? 0.0).toDouble(),
      type: json['tax_type'] ?? json['type'] ?? 'tax',
      isDefault: json['is_default_tax'] ?? json['isDefault'] ?? false,
    );
  }

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
