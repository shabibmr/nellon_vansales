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

  /// Company street / postal address for tickets and letterheads.
  final String address;

  /// Company phone number for tickets and letterheads.
  final String phone;

  /// Company tax registration number (e.g. UAE TRN).
  final String trn;

  /// Number of decimal places used for monetary display and calculations.
  /// Defaults to 2 when omitted.
  final int currencyDecimalPlaces;

  /// Step Zoho rounds document totals to (e.g. 0.5), detected from recent
  /// invoices. 0 means totals are not cash-rounded.
  final double totalRoundingStep;

  /// Creates a new [Organization] configuration.
  const Organization({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.currencySymbol,
    required this.fiscalYearStartMonth,
    required this.timeZone,
    this.address = '',
    this.phone = '',
    this.trn = '',
    int? currencyDecimalPlaces,
    this.totalRoundingStep = 0,
  }) : currencyDecimalPlaces = currencyDecimalPlaces ?? 2;

  /// Formats [value] using this organization's symbol and decimal places.
  String formatCurrency(double value, {int? decimals}) {
    final d = decimals ?? currencyDecimalPlaces;
    return '$currencySymbol${value.toStringAsFixed(d)}';
  }

  /// Creates a copy of this [Organization] with replaced values for specific fields.
  Organization copyWith({
    String? id,
    String? name,
    String? currencyCode,
    String? currencySymbol,
    String? fiscalYearStartMonth,
    String? timeZone,
    String? address,
    String? phone,
    String? trn,
    int? currencyDecimalPlaces,
    double? totalRoundingStep,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      fiscalYearStartMonth: fiscalYearStartMonth ?? this.fiscalYearStartMonth,
      timeZone: timeZone ?? this.timeZone,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      trn: trn ?? this.trn,
      currencyDecimalPlaces:
          currencyDecimalPlaces ?? this.currencyDecimalPlaces,
      totalRoundingStep: totalRoundingStep ?? this.totalRoundingStep,
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
        address,
        phone,
        trn,
        currencyDecimalPlaces,
        totalRoundingStep,
      ];
}
