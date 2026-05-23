import 'package:equatable/equatable.dart';

class Tax extends Equatable {
  final String id; // Zoho tax_id
  final String name;
  final double percentage;
  final String type; // tax | compound_tax | tax_group
  final bool isDefault;

  const Tax({
    required this.id,
    required this.name,
    required this.percentage,
    required this.type,
    this.isDefault = false,
  });

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
