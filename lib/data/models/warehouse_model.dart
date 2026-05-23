import '../../domain/models/warehouse.dart';

class WarehouseModel extends Warehouse {
  const WarehouseModel({
    required super.id,
    required super.name,
    required super.address,
    super.isPrimary,
  });

  factory WarehouseModel.fromJson(Map<String, dynamic> json) {
    return WarehouseModel(
      id: json['warehouse_id'] ?? json['id'] ?? '',
      name: json['warehouse_name'] ?? json['name'] ?? '',
      address: json['address'] ?? '',
      isPrimary: json['is_primary'] ?? json['isPrimary'] ?? false,
    );
  }

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

  factory WarehouseModel.fromDomain(Warehouse w) {
    return WarehouseModel(
      id: w.id,
      name: w.name,
      address: w.address,
      isPrimary: w.isPrimary,
    );
  }
}
