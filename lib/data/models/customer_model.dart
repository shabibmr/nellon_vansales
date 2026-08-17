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
    super.trn,
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
  /// - native billing_address / shipping_address {latitude, longitude}
  /// - top-level latitude / lat / cf_latitude
  /// - custom_field_hash map
  /// - custom_fields array of {api_name, value} or {label, value}
  static (double?, double?) _extractGps(Map<String, dynamic> json) {
    final billing = json['billing_address'] is Map
        ? json['billing_address'] as Map
        : null;
    final shipping = json['shipping_address'] is Map
        ? json['shipping_address'] as Map
        : null;

    double? lat = _parseLatLng(
      billing?['latitude'] ??
          shipping?['latitude'] ??
          json['latitude'] ??
          json['lat'] ??
          json['cf_latitude'] ??
          json['custom_field_hash']?['cf_latitude'] ??
          json['custom_field_hash']?['latitude'],
    );

    double? lng = _parseLatLng(
      billing?['longitude'] ??
          shipping?['longitude'] ??
          json['longitude'] ??
          json['lng'] ??
          json['long'] ??
          json['cf_longitude'] ??
          json['custom_field_hash']?['cf_longitude'] ??
          json['custom_field_hash']?['longitude'],
    );

    // Fallback: scan custom_fields array
    final cfs = json['custom_fields'];
    if (cfs is List && (lat == null || lng == null)) {
      for (final item in cfs) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final api =
            (m['api_name'] ?? m['field_name'] ?? '').toString().toLowerCase();
        final label = (m['label'] ?? '').toString().toLowerCase();
        final val = m['value'];

        if (lat == null &&
            (api.contains('latitude') ||
                label.contains('latitude') ||
                api == 'cf_latitude')) {
          lat = _parseLatLng(val);
        }
        if (lng == null &&
            (api.contains('longitude') ||
                label.contains('longitude') ||
                api == 'cf_longitude')) {
          lng = _parseLatLng(val);
        }
      }
    }

    return (lat, lng);
  }

  static String _extractTrn(Map<String, dynamic> json) {
    final direct = _firstNonEmpty([
      json['tax_reg_no'],
      json['vat_reg_no'],
      json['trn'],
      json['taxRegNo'],
      json['tax_number'],
      json['tax_id'],
      json['custom_field_hash']?['cf_trn'],
      json['custom_field_hash']?['tax_reg_no'],
    ]);
    if (direct.isNotEmpty) return direct;

    final cfs = json['custom_fields'];
    if (cfs is List) {
      for (final item in cfs) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final api =
            (m['api_name'] ?? m['field_name'] ?? '').toString().toLowerCase();
        final label = (m['label'] ?? '').toString().toLowerCase();
        if (api.contains('trn') ||
            api.contains('tax_reg') ||
            label.contains('trn') ||
            label.contains('tax reg')) {
          final v = (m['value'] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
    }
    return '';
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// Factory constructor to parse local/remote JSON payload into a [CustomerModel].
  ///
  /// Maps server keys (`contact_id`, `contact_name`, `outstanding_receivable_amount`)
  /// and local database representations fallback keys. Also extracts GPS from
  /// custom fields (cf_latitude / cf_longitude or custom_fields array).
  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    final (lat, lng) = _extractGps(json);

    return CustomerModel(
      id: ((json['contact_id'] ?? json['id']) as String?) ?? '',
      name: ((json['contact_name'] ?? json['name']) as String?) ?? '',
      companyName:
          ((json['company_name'] ?? json['companyName']) as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      phone: _firstNonEmpty([
        json['phone'],
        json['mobile'],
        json['mobile_phone'],
      ]),
      address: ((json['address'] ??
                  (json['billing_address'] as Map?)?['address']) as String?) ??
          '',
      trn: _extractTrn(json),
      outstandingBalance: ((json['outstanding_receivable_amount'] ??
                  json['outstanding_balance'] ??
                  json['outstandingBalance']) as num?)
              ?.toDouble() ??
          0.0,
      creditLimit:
          ((json['credit_limit'] ?? json['creditLimit']) as num?)?.toDouble() ??
              0.0,
      routeId: ((json['route_id'] ?? json['routeId']) as String?) ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      latitude: lat,
      longitude: lng,
      isPendingSync: (json['isPendingSync'] as bool?) ?? false,
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
      'trn': trn,
      'tax_reg_no': trn,
      'outstandingBalance': outstandingBalance,
      'creditLimit': creditLimit,
      'route_id': routeId,
      'sequence': sequence,
      'isPendingSync': isPendingSync,
    };
    if (latitude != null) map['latitude'] = latitude;
    if (longitude != null) map['longitude'] = longitude;
    if (address.isNotEmpty || latitude != null || longitude != null) {
      map['billing_address'] = {
        if (address.isNotEmpty) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
    }
    // Also expose cf_ keys for backwards compatibility
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
      trn: customer.trn,
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
