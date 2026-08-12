import '../../domain/models/organization.dart';

/// Data transfer object representing the [Organization] config.
///
/// Parses localized parameters (currency codes, symbols, fiscal configuration) from Zoho's settings API.
class OrganizationModel extends Organization {
  /// Creates a new [OrganizationModel] instance.
  const OrganizationModel({
    required super.id,
    required super.name,
    required super.currencyCode,
    required super.currencySymbol,
    required super.fiscalYearStartMonth,
    required super.timeZone,
    super.address,
    super.phone,
    super.trn,
  });

  /// Factory constructor to parse local/remote JSON maps into an [OrganizationModel].
  ///
  /// Maps keys (`organization_id`, `currency_code`, address/phone/tax fields).
  factory OrganizationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationModel(
      id: ((json['organization_id'] ?? json['id']) as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      currencyCode:
          ((json['currency_code'] ?? json['currencyCode']) as String?) ?? '',
      currencySymbol:
          ((json['currency_symbol'] ?? json['currencySymbol']) as String?) ??
              '',
      fiscalYearStartMonth: ((json['fiscal_year_start_month'] ??
                  json['fiscalYearStartMonth']) as String?) ??
          'january',
      timeZone: ((json['time_zone'] ?? json['timeZone']) as String?) ?? '',
      address: _extractAddress(json),
      phone: _firstNonEmpty([
        json['phone'],
        json['mobile'],
        json['contact_number'],
        json['company_phone'],
      ]),
      trn: _firstNonEmpty([
        json['tax_reg_no'],
        json['tax_id'],
        json['tax_number'],
        json['trn'],
        json['taxRegNo'],
      ]),
    );
  }

  /// Converts this [OrganizationModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': id,
      'name': name,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'fiscal_year_start_month': fiscalYearStartMonth,
      'time_zone': timeZone,
      'address': address,
      'phone': phone,
      'trn': trn,
      'tax_reg_no': trn,
    };
  }

  /// Translates a base domain [Organization] entity into its [OrganizationModel] DTO representation.
  factory OrganizationModel.fromDomain(Organization o) {
    return OrganizationModel(
      id: o.id,
      name: o.name,
      currencyCode: o.currencyCode,
      currencySymbol: o.currencySymbol,
      fiscalYearStartMonth: o.fiscalYearStartMonth,
      timeZone: o.timeZone,
      address: o.address,
      phone: o.phone,
      trn: o.trn,
    );
  }

  static String _extractAddress(Map<String, dynamic> json) {
    final direct = _firstNonEmpty([
      json['address'],
      json['company_address'],
      json['org_address'],
    ]);
    if (direct.isNotEmpty) return direct;

    // Zoho org payloads often split address into street/city/state/zip/country.
    final parts = <String>[
      _asString(json['street_address1'] ?? json['address1']),
      _asString(json['street_address2'] ?? json['address2']),
      _asString(json['city']),
      _asString(json['state']),
      _asString(json['zip'] ?? json['zipcode'] ?? json['postal_code']),
      _asString(json['country']),
    ].where((p) => p.isNotEmpty).toList();

    if (parts.isNotEmpty) return parts.join(', ');

    final nested = json['address'];
    if (nested is Map) {
      final m = Map<String, dynamic>.from(nested);
      final nestedParts = <String>[
        _asString(m['street_address1'] ?? m['address'] ?? m['address1']),
        _asString(m['street_address2'] ?? m['address2']),
        _asString(m['city']),
        _asString(m['state']),
        _asString(m['zip'] ?? m['zipcode']),
        _asString(m['country']),
      ].where((p) => p.isNotEmpty).toList();
      return nestedParts.join(', ');
    }

    return '';
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = _asString(v);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _asString(dynamic v) {
    if (v == null) return '';
    return v.toString().trim();
  }
}
