import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/theme/app_theme.dart';

class ItemDetailsDialog extends StatelessWidget {
  final Item item;

  const ItemDetailsDialog({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SKU: ${item.sku}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Rate: ₹${item.rate.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          Text('Tax Group: ${item.taxName} (${item.taxPercentage}%)'),
          const SizedBox(height: 8),
          Text(
            'Available in Van: ${item.stock} units',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: item.stock > 0 ? AppTheme.successEmerald : AppTheme.errorRose,
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
        )
      ],
    );
  }
}
