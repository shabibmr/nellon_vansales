import 'package:flutter/material.dart';
import '../../../core/cubit/line_editor_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';

class ItemLineEditorTotals extends StatelessWidget {
  final bool wide;
  final bool isDark;
  final String currencySymbol;
  final double taxPercentage;
  final LineEditorState state;

  const ItemLineEditorTotals({
    super.key,
    required this.wide,
    required this.isDark,
    required this.currencySymbol,
    required this.taxPercentage,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final cells = [
      _TotalCell(
        label: 'Subtotal',
        value: formatCurrency(state.subtotal, currencySymbol),
      ),
      _TotalCell(
        label: 'Discount',
        value: formatCurrency(state.discount, currencySymbol),
        valueColor: AppTheme.errorRose,
      ),
      _TotalCell(
        label: 'VAT ($taxPercentage%)',
        value: formatCurrency(state.taxAmount, currencySymbol),
      ),
      _TotalCell(
        label: 'Total',
        value: formatCurrency(state.total, currencySymbol),
        bold: true,
        valueColor: AppTheme.primaryIndigo,
      ),
    ];

    final grid = wide
        ? Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: cells[i]),
              ],
            ],
          )
        : Column(
            children: [
              Row(
                children: [
                  Expanded(child: cells[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cells[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cells[2]),
                  const SizedBox(width: 8),
                  Expanded(child: cells[3]),
                ],
              ),
            ],
          );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: grid,
    );
  }
}

class _TotalCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _TotalCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 13 : 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
