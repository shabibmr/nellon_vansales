import 'package:equatable/equatable.dart';

/// Represents a Tax bracket configuration from Zoho Books.
///
/// Applied to billing items when generating invoices or processing returns to calculate tax amounts correctly.
class Tax extends Equatable {
  /// Unique tax identifier from Zoho (tax_id).
  final String id;

  /// The name/label of the tax (e.g. "VAT (5%)", "Zero Tax").
  final String name;

  /// Tax rate percentage value (e.g. 5.0).
  final double percentage;

  /// The classification type of tax (e.g. "tax", "compound_tax", "tax_group").
  final String type;

  /// Flag indicating if this is the default tax applied when no tax is specified on an item.
  final bool isDefault;

  /// Creates a new [Tax] configuration record.
  const Tax({
    required this.id,
    required this.name,
    required this.percentage,
    required this.type,
    this.isDefault = false,
  });

  /// Creates a copy of this [Tax] with replaced values for specific fields.
  Tax copyWith({
    String? id,
    String? name,
    double? percentage,
    String? type,
    bool? isDefault,
  }) {
    return Tax(
      id: id ?? this.id,
      name: name ?? this.name,
      percentage: percentage ?? this.percentage,
      type: type ?? this.type,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  List<Object?> get props => [id, name, percentage, type, isDefault];
}

