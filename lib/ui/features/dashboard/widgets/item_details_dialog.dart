import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';

/// Modal dialog displaying comprehensive, read-only specifications of a stocked inventory [Item].
class ItemDetailsDialog extends StatelessWidget {
  /// The inventory item profile to show.
  final Item item;

  /// Creates a new [ItemDetailsDialog].
  const ItemDetailsDialog({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    return AlertDialog(
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SKU: ${item.sku}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Rate: $cs${item.rate.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          Text('Tax Group: ${item.taxName} (${item.taxPercentage}%)'),
          const SizedBox(height: 8),
          Text(
            'Available in Van: ${item.stock} units',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: item.stock > 0
                  ? AppTheme.successEmerald
                  : AppTheme.errorRose,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.description,
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}
