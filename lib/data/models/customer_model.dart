import '../../domain/models/customer.dart';

/// Data transfer object for the [Customer] domain entity.
///
/// Implements robust JSON parsing to support both offline database hydration and
/// remote Zoho CRM Contact API maps, resolving differences in naming conventions (snake_case vs camelCase).
class CustomerModel extends Customer {
  /// Creates a new [CustomerModel] instance matching fields of the parent.
  const CustomerModel({
    required super.id,
    required super.name,
    required super.companyName,
    required super.email,
    required super.phone,
    required super.address,
    required super.outstandingBalance,
    required super.creditLimit,
    required super.routeId,
    required super.sequence,
    super.latitude,
    super.longitude,
    super.isPendingSync,
  });

  /// Helper to robustly parse a nullable double from common representations.
  static double? _parseLatLng(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Extracts GPS latitude/longitude from Zoho contact JSON.
  ///
  /// Supports multiple shapes seen in practice:
  /// - top-level cf_latitude / latitude / lat
  /// - custom_field_hash map
  /// - custom_fields array of {api_name, value} or {label, value}
  static (double?, double?) _extractGps(Map<String, dynamic> json) {
    double? lat = _parseLatLng(json['cf_latitude'] ??
        json['latitude'] ??
        json['lat'] ??
        json['custom_field_hash']?['cf_latitude'] ??
        json['custom_field_hash']?['latitude']);

    double? lng = _parseLatLng(json['cf_longitude'] ??
        json['longitude'] ??
        json['lng'] ??
        json['long'] ??
        json['custom_field_hash']?['cf_longitude'] ??
        json['custom_field_hash']?['longitude']);

    // Fallback: scan custom_fields array
    final cfs = json['custom_fields'];
    if (cfs is List && (lat == null || lng == null)) {
      for (final item in cfs) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final api = (m['api_name'] ?? m['field_name'] ?? '').toString().toLowerCase();
        final label = (m['label'] ?? '').toString().toLowerCase();
        final val = m['value'];

        if (lat == null &&
            (api.contains('latitude') || label.contains('latitude') || api == 'cf_latitude')) {
          lat = _parseLatLng(val);
        }
        if (lng == null &&
            (api.contains('longitude') || label.contains('longitude') || api == 'cf_longitude')) {
          lng = _parseLatLng(val);
        }
      }
    }

    return (lat, lng);
  }

  /// Factory constructor to parse local/remote JSON payload into a [CustomerModel].
  ///
  /// Maps server keys (`contact_id`, `contact_name`, `outstanding_receivable_amount`)
  /// and local database representations fallback keys. Also extracts GPS from
  /// custom fields (cf_latitude / cf_longitude or custom_fields array).
  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    final (lat, lng) = _extractGps(json);

    return CustomerModel(
      id: json['contact_id'] ?? json['id'] ?? '',
      name: json['contact_name'] ?? json['name'] ?? '',
      companyName: json['company_name'] ?? json['companyName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? json['billing_address']?['address'] ?? '',
      outstandingBalance:
          (json['outstanding_receivable_amount'] ??
                  json['outstanding_balance'] ??
                  json['outstandingBalance'] ??
                  0.0)
              .toDouble(),
      creditLimit: (json['credit_limit'] ?? json['creditLimit'] ?? 0.0)
          .toDouble(),
      routeId: json['route_id'] ?? json['routeId'] ?? '',
      sequence: json['sequence'] ?? 0,
      latitude: lat,
      longitude: lng,
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

  /// Converts this [CustomerModel] instance into a JSON compatible map.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'contact_id': id,
      'name': name,
      'contact_name': name,
      'company_name': companyName,
      'email': email,
      'phone': phone,
      'address': address,
      'outstandingBalance': outstandingBalance,
      'creditLimit': creditLimit,
      'route_id': routeId,
      'sequence': sequence,
      'isPendingSync': isPendingSync,
    };
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    // Also expose cf_ keys for direct Zoho payload convenience in some flows
    if (latitude != null) map['cf_latitude'] = latitude;
    if (longitude != null) map['cf_longitude'] = longitude;
    return map;
  }

  /// Facilitates converting a base domain [Customer] entity into a serializable [CustomerModel].
  factory CustomerModel.fromDomain(Customer customer) {
    return CustomerModel(
      id: customer.id,
      name: customer.name,
      companyName: customer.companyName,
      email: customer.email,
      phone: customer.phone,
      address: customer.address,
      outstandingBalance: customer.outstandingBalance,
      creditLimit: customer.creditLimit,
      routeId: customer.routeId,
      sequence: customer.sequence,
      latitude: customer.latitude,
      longitude: customer.longitude,
      isPendingSync: customer.isPendingSync,
    );
  }
}
