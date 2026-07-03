import 'package:equatable/equatable.dart';

/// Represents a Zoho Books Organization details configuration.
///
/// Contains settings like currency formatting, timezones, and fiscal structure
/// to ensure local calculations (such as invoices and payments) match the backend organization context.
class Organization extends Equatable {
  /// Unique organization identifier from Zoho.
  final String id;

  /// The official name of the organization.
  final String name;

  /// Currency code of the organization (e.g. "USD", "INR", "AED").
  final String currencyCode;

  /// Currency symbol of the organization (e.g. "$", "₹", "AED").
  final String currencySymbol;

  /// Starting month index of the fiscal year (e.g. "1" for January).
  final String fiscalYearStartMonth;

  /// Standard timezone representation of the organization's location.
  final String timeZone;

  /// Creates a new [Organization] configuration.
  const Organization({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.currencySymbol,
    required this.fiscalYearStartMonth,
    required this.timeZone,
  });

  /// Creates a copy of this [Organization] with replaced values for specific fields.
  Organization copyWith({
    String? id,
    String? name,
    String? currencyCode,
    String? currencySymbol,
    String? fiscalYearStartMonth,
    String? timeZone,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      fiscalYearStartMonth: fiscalYearStartMonth ?? this.fiscalYearStartMonth,
      timeZone: timeZone ?? this.timeZone,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    currencyCode,
    currencySymbol,
    fiscalYearStartMonth,
    timeZone,
  ];
}
