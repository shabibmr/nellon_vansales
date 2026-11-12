import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/utils/money_math.dart';
import '../cubit/organization_cubit.dart';

/// A dedicated base widget for displaying monetary values.
///
/// Automatically reads the active currency symbol and decimal places from
/// [OrganizationCubit] via `context.watch<OrganizationCubit>()` so it updates
/// reactively, eliminating repetitive manual string formatting across the UI.
class AppCurrencyText extends StatelessWidget {
  /// The numeric money amount to display.
  final double amount;

  /// Optional text styling.
  final TextStyle? style;

  /// How the text should be aligned horizontally.
  final TextAlign? textAlign;

  /// How visual overflow should be handled.
  final TextOverflow? overflow;

  /// An optional maximum number of lines for the text to span.
  final int? maxLines;

  /// An alternative semantics label for accessibility.
  final String? semanticsLabel;

  /// Optional string prepended before the currency output (e.g. "Total: ", "+").
  final String? prefix;

  /// Optional string appended after the currency output (e.g. " (inc. VAT)").
  final String? suffix;

  /// Whether to include the currency symbol in the output. Defaults to true.
  final bool showSymbol;

  /// Optional explicit override for the currency symbol.
  /// If omitted, reads [OrganizationCubit.currencySymbol].
  final String? symbol;

  /// Optional explicit override for the decimal places count.
  /// If omitted, reads [OrganizationCubit.currencyDecimalPlaces].
  final int? decimals;

  const AppCurrencyText({
    super.key,
    required this.amount,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.semanticsLabel,
    this.prefix,
    this.suffix,
    this.showSymbol = true,
    this.symbol,
    this.decimals,
  });

  @override
  Widget build(BuildContext context) {
    OrganizationCubit? cubit;
    try {
      cubit = context.watch<OrganizationCubit>();
    } catch (_) {
      try {
        cubit = context.read<OrganizationCubit>();
      } catch (_) {
        cubit = null;
      }
    }

    final resolvedSymbol = symbol ?? cubit?.currencySymbol ?? '';
    final resolvedDecimals = decimals ??
        cubit?.currencyDecimalPlaces ??
        MoneyScale.decimals;

    final formattedNumber = amount.toStringAsFixed(resolvedDecimals);
    final core = showSymbol ? '$resolvedSymbol$formattedNumber' : formattedNumber;
    final text = '${prefix ?? ''}$core${suffix ?? ''}';

    return Text(
      text,
      style: style,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
    );
  }
}
