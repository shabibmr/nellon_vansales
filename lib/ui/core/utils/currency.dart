import '../../../domain/utils/money_math.dart';

/// Formats a monetary [value] with a currency [symbol] and [decimals].
///
/// If [decimals] is omitted, uses [MoneyScale.decimals] (2 until an org loads).
String formatCurrency(double value, String symbol, {int? decimals}) {
  final d = decimals ?? MoneyScale.decimals;
  return '$symbol${value.toStringAsFixed(d)}';
}

/// Formats [value] with [MoneyScale] decimals and no currency symbol.
String formatMoneyNumber(double value, {int? decimals}) {
  return value.toStringAsFixed(decimals ?? MoneyScale.decimals);
}
