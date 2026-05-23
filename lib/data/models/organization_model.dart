import '../../domain/models/organization.dart';

class OrganizationModel extends Organization {
  const OrganizationModel({
    required super.id,
    required super.name,
    required super.currencyCode,
    required super.currencySymbol,
    required super.fiscalYearStartMonth,
    required super.timeZone,
  });

  factory OrganizationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationModel(
      id: json['organization_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      currencyCode: json['currency_code'] ?? json['currencyCode'] ?? '',
      currencySymbol: json['currency_symbol'] ?? json['currencySymbol'] ?? '',
      fiscalYearStartMonth:
          json['fiscal_year_start_month'] ?? json['fiscalYearStartMonth'] ?? 'january',
      timeZone: json['time_zone'] ?? json['timeZone'] ?? '',
    );
  }

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
