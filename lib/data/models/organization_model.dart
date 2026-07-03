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
  });

  /// Factory constructor to parse local/remote JSON maps into an [OrganizationModel].
  ///
  /// Mappes keys (`organization_id`, `currency_code`, `currency_symbol`, `fiscal_year_start_month`) correctly.
  factory OrganizationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationModel(
      id: json['organization_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      currencyCode: json['currency_code'] ?? json['currencyCode'] ?? '',
      currencySymbol: json['currency_symbol'] ?? json['currencySymbol'] ?? '',
      fiscalYearStartMonth:
          json['fiscal_year_start_month'] ??
          json['fiscalYearStartMonth'] ??
          'january',
      timeZone: json['time_zone'] ?? json['timeZone'] ?? '',
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
    );
  }
}
