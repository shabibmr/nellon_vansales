import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';

/// A single editable line-item row shared by order/invoice/return editors.
class LineItemRow {
  final String name;
  final String sku;
  final double rate;
  final double taxPercentage;
  final int quantity;
  final double total;
  final double discount;
  final Color accentColor;

  const LineItemRow({
    required this.name,
    required this.sku,
    required this.rate,
    required this.taxPercentage,
    required this.quantity,
    required this.total,
    this.discount = 0.0,
    this.accentColor = AppTheme.primaryIndigo,
  });
}

/// Shared non-scrollable list of line item cards for editor pages.
class LineItemList extends StatelessWidget {
  final List<LineItemRow> items;
  final String currencySymbol;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;

  const LineItemList({
    super.key,
    required this.items,
    required this.currencySymbol,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final line = items[index];
        return Card(
          child: InkWell(
            onTap: () => onEdit(index),
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
                          'SKU: ${line.sku} | Rate: ${formatCurrency(line.rate, currencySymbol)} | VAT: ${line.taxPercentage}%'
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
                        'Qty: ${line.quantity}',
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
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppTheme.errorRose,
                      size: 20,
                    ),
                    onPressed: () => onRemove(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
