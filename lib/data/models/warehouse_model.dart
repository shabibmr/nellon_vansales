import '../../domain/models/warehouse.dart';

/// Data transfer object representing a [Warehouse] entity.
///
/// Converts between raw API responses and the local representation of stock rooms/van inventory chambers.
class WarehouseModel extends Warehouse {
  /// Creates a new [WarehouseModel] instance.
  const WarehouseModel({
    required super.id,
    required super.name,
    required super.address,
    super.isPrimary,
  });

  /// Factory constructor to parse local/remote JSON maps into a [WarehouseModel].
  ///
  /// Mappes Zoho API keys (`warehouse_id`, `warehouse_name`, `is_primary`) to their parent domains.
  factory WarehouseModel.fromJson(Map<String, dynamic> json) {
    return WarehouseModel(
      id: json['warehouse_id'] ?? json['id'] ?? '',
      name: json['warehouse_name'] ?? json['name'] ?? '',
      address: json['address'] ?? '',
      isPrimary: json['is_primary'] ?? json['isPrimary'] ?? false,
    );
  }

  /// Converts this [WarehouseModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warehouse_id': id,
      'name': name,
      'warehouse_name': name,
      'address': address,
      'is_primary': isPrimary,
    };
  }

  /// Translates a base domain [Warehouse] entity into a serializable [WarehouseModel].
  factory WarehouseModel.fromDomain(Warehouse w) {
    return WarehouseModel(
      id: w.id,
      name: w.name,
      address: w.address,
      isPrimary: w.isPrimary,
    );
  }
}
