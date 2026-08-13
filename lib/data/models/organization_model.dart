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
      trn: _extractTrn(json),
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

  /// UAE Books puts the TRN on [tax_settings.tax_reg_no], not [tax_id_value].
  static String _extractTrn(Map<String, dynamic> json) {
    final settings = json['tax_settings'];
    if (settings is Map) {
      final fromSettings = _asString(settings['tax_reg_no']);
      if (fromSettings.isNotEmpty) return fromSettings;
    }

    final fromCustom = _trnFromCustomFields(json);
    if (fromCustom.isNotEmpty) return fromCustom;

    return _firstNonEmpty([
      json['tax_reg_no'],
      json['tax_number'],
      json['trn'],
      json['taxRegNo'],
    ]);
  }

  static String _trnFromCustomFields(Map<String, dynamic> json) {
    final cfs = json['custom_fields'];
    if (cfs is! List) return '';
    for (final item in cfs) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final label = _asString(m['label']).toLowerCase();
      final api = _asString(m['api_name'] ?? m['field_name']).toLowerCase();
      if (label.contains('trn') || api.contains('trn')) {
        final value = _asString(m['value']);
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  static String _extractAddress(Map<String, dynamic> json) {
    for (final key in ['address', 'company_address', 'org_address']) {
      final formatted = _formatAddressField(json[key]);
      if (formatted.isNotEmpty) return formatted;
    }

    return _joinAddressParts([
      json['street_address1'] ?? json['address1'],
      json['street_address2'] ?? json['address2'],
      json['city'],
      json['state'],
      json['zip'] ?? json['zipcode'] ?? json['postal_code'],
      json['country'],
    ]);
  }

  static String _formatAddressField(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map) {
      final m = Map<String, dynamic>.from(value);
      return _joinAddressParts([
        m['street_address1'] ?? m['address'] ?? m['address1'],
        m['street_address2'] ?? m['address2'] ?? m['street2'],
        m['city'],
        m['state'],
        m['zip'] ?? m['zipcode'],
        m['country'],
      ]);
    }
    return '';
  }

  static String _joinAddressParts(List<dynamic> raw) {
    final parts = <String>[];
    for (final part in raw) {
      final s = _asString(part);
      if (s.isEmpty) continue;
      if (_alreadyContains(parts, s)) continue;
      parts.add(s);
    }
    return parts.join(', ');
  }

  static bool _alreadyContains(List<String> existing, String candidate) {
    final token = _normalizeAddressToken(candidate);
    if (token.isEmpty) return true;
    final joined = existing.map(_normalizeAddressToken).join(' ');
    return joined.contains(token);
  }

  static String _normalizeAddressToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = _asString(v);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _asString(dynamic v) {
    if (v == null || v is Map || v is List) return '';
    return v.toString().trim();
  }
}
