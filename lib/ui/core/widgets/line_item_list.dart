import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../utils/quantity_format.dart';

/// A single editable line-item row shared by order/invoice/return editors.
class LineItemRow {
  final String name;
  final String sku;
  final double rate;
  final double taxPercentage;
  final double quantity;
  final double total;
  final double discount;
  /// Unit of measure label (e.g. pcs, kg). Empty when unknown.
  final String uom;
  final Color accentColor;

  const LineItemRow({
    required this.name,
    required this.sku,
    required this.rate,
    required this.taxPercentage,
    required this.quantity,
    required this.total,
    this.discount = 0.0,
    this.uom = '',
    this.accentColor = AppTheme.primaryIndigo,
  });
}

/// Shared non-scrollable list of line item cards for editor pages.
///
/// When [onEdit] / [onRemove] are null the row is view-only (no tap, no delete).
class LineItemList extends StatelessWidget {
  final List<LineItemRow> items;
  final String currencySymbol;
  final void Function(int index)? onEdit;
  final void Function(int index)? onRemove;

  const LineItemList({
    super.key,
    required this.items,
    required this.currencySymbol,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editable = onEdit != null || onRemove != null;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final line = items[index];
        return Card(
          child: InkWell(
            onTap: onEdit == null ? null : () => onEdit!(index),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: ${line.sku}'
                          '${line.uom.isNotEmpty ? ' | UOM: ${line.uom}' : ''}'
                          ' | Rate: ${formatCurrency(line.rate, currencySymbol)} | VAT: ${line.taxPercentage}%'
                          '${line.discount > 0 ? ' | Disc: ${formatCurrency(line.discount, currencySymbol)}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        line.uom.isNotEmpty
                            ? 'Qty: ${formatQuantity(line.quantity)} ${line.uom}'
                            : 'Qty: ${formatQuantity(line.quantity)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatCurrency(line.total, currencySymbol),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: line.accentColor,
                        ),
                      ),
                    ],
                  ),
                  if (onRemove != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove line item',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppTheme.errorRose,
                        size: 20,
                      ),
                      onPressed: () => onRemove!(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                    ),
                  ] else if (!editable)
                    const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
