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
  /// Supports parsing Zoho Books Locations (e.g. `location_id`, `location_name`, `is_primary_location`)
  /// as well as fallback Zoho Warehouses properties.
  factory WarehouseModel.fromJson(Map<String, dynamic> json) {
    final id = json['location_id'] ?? json['warehouse_id'] ?? json['id'] ?? '';
    final name = json['location_name'] ?? json['warehouse_name'] ?? json['name'] ?? '';
    
    String addressStr = '';
    final addressRaw = json['address'];
    if (addressRaw is Map) {
      final parts = <String>[];
      if (addressRaw['street_address1'] != null && addressRaw['street_address1'].toString().trim().isNotEmpty) {
        parts.add(addressRaw['street_address1'].toString().trim());
      }
      if (addressRaw['street_address2'] != null && addressRaw['street_address2'].toString().trim().isNotEmpty) {
        parts.add(addressRaw['street_address2'].toString().trim());
      }
      if (addressRaw['city'] != null && addressRaw['city'].toString().trim().isNotEmpty) {
        parts.add(addressRaw['city'].toString().trim());
      }
      if (addressRaw['state'] != null && addressRaw['state'].toString().trim().isNotEmpty) {
        parts.add(addressRaw['state'].toString().trim());
      }
      if (addressRaw['country'] != null && addressRaw['country'].toString().trim().isNotEmpty) {
        parts.add(addressRaw['country'].toString().trim());
      }
      addressStr = parts.join(', ');
    } else if (addressRaw != null) {
      addressStr = addressRaw.toString();
    }

    final isPrimary = json['is_primary_location'] ?? json['is_location_primary'] ?? json['is_primary'] ?? json['isPrimary'] ?? false;

    return WarehouseModel(
      id: id.toString(),
      name: name.toString(),
      address: addressStr,
      isPrimary: isPrimary == true,
    );
  }

  /// Converts this [WarehouseModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warehouse_id': id,
      'location_id': id,
      'name': name,
      'warehouse_name': name,
      'location_name': name,
      'address': address,
      'is_primary': isPrimary,
      'is_primary_location': isPrimary,
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
