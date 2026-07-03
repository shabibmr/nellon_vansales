import '../../domain/models/salesperson.dart';

/// Data transfer object representing a [Salesperson] entity.
///
/// Converts between raw Zoho Books API responses (and local Hive cache JSON) and
/// the local domain representation.
class SalespersonModel extends Salesperson {
  /// Creates a new [SalespersonModel] instance.
  const SalespersonModel({
    required super.id,
    required super.name,
    required super.email,
    super.locationId,
    super.status,
  });

  /// Factory constructor to parse local/remote JSON maps into a [SalespersonModel].
  ///
  /// Supports Zoho Books' native Salesperson fields (`salesperson_id`,
  /// `salesperson_name`, `salesperson_email`) as well as fallback generic keys.
  factory SalespersonModel.fromJson(Map<String, dynamic> json) {
    final id = json['salesperson_id'] ?? json['id'] ?? '';
    final name = json['salesperson_name'] ?? json['name'] ?? '';
    final email = json['salesperson_email'] ?? json['email'] ?? '';
    final locationId = json['location_id'] ?? json['locationId'];

    // Zoho reports lifecycle as boolean `is_active` (verified against live API);
    // locally cached records round-trip a `status` string instead.
    final String status;
    if (json.containsKey('is_active')) {
      status = json['is_active'] == true ? 'active' : 'inactive';
    } else {
      status = (json['status'] ?? 'active').toString();
    }

    return SalespersonModel(
      id: id.toString(),
      name: name.toString(),
      email: email.toString(),
      locationId: locationId?.toString(),
      status: status,
    );
  }

  /// Converts this [SalespersonModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'salesperson_id': id,
      'salesperson_name': name,
      'name': name,
      'salesperson_email': email,
      'email': email,
      'location_id': locationId,
      'status': status,
    };
  }

  /// Translates a base domain [Salesperson] entity into a serializable [SalespersonModel].
  factory SalespersonModel.fromDomain(Salesperson s) {
    return SalespersonModel(
      id: s.id,
      name: s.name,
      email: s.email,
      locationId: s.locationId,
      status: s.status,
    );
  }
}
