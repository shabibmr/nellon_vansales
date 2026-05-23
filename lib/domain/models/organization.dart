import 'package:equatable/equatable.dart';

class Organization extends Equatable {
  final String id;
  final String name;
  final String currencyCode;
  final String currencySymbol;
  final String fiscalYearStartMonth;
  final String timeZone;

  const Organization({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.currencySymbol,
    required this.fiscalYearStartMonth,
    required this.timeZone,
  });

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
  List<Object?> get props =>
      [id, name, currencyCode, currencySymbol, fiscalYearStartMonth, timeZone];
}
