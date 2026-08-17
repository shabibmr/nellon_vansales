import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_format.dart';
import '../bloc/stock_transfer_bloc.dart';

/// A single line tile in the stock-transfer editor listview: item identity,
/// current stock, the entered transfer quantity, and the resulting grand
/// total (current + qty). No rate/tax — transfer lines carry no money.
///
/// Tap opens the quantity dialog ([onTap]); the remove button fires
/// [onRemove]. Both are null in read-only mode (viewing a processed
/// transfer).
class StockTransferLineTile extends StatelessWidget {
  final StockTransferRow row;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const StockTransferLineTile({
    super.key,
    required this.row,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final uom = row.displayUom;

    return Card(
      child: InkWell(
        onTap: onTap,
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
                      row.item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${row.item.sku}'
                      '${uom.isNotEmpty ? ' | UOM: $uom' : ''}'
                      ' | Current: ${formatQuantity(row.currentStock)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Qty: ${formatQuantity(row.extraQtyEntered)}'
                    '${uom.isNotEmpty ? ' $uom' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Grand: ${formatQuantity(row.grandTotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.primaryIndigo,
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
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
