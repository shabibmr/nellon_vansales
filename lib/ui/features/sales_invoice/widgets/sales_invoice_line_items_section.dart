import 'package:flutter/material.dart';

import '../../../../domain/models/sales_invoice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/line_item_list.dart';

class SalesInvoiceLineItemsSection extends StatelessWidget {
  final List<InvoiceLineItem> items;
  final String currencySymbol;
  final bool readOnly;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  const SalesInvoiceLineItemsSection({
    super.key,
    required this.items,
    required this.currencySymbol,
    required this.readOnly,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LINE ITEMS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (!readOnly)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('ADD ITEM'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'No Items Added',
            message: readOnly
                ? 'This invoice has no line items.'
                : 'Tap "ADD ITEM" above to add products to this invoice.',
          )
        else
          LineItemList(
            items: items
                .map(
                  (line) => LineItemRow(
                    name: line.item.name,
                    sku: line.item.sku,
                    rate: line.rate,
                    taxPercentage: line.taxPercentage,
                    quantity: line.quantity,
                    total: line.total,
                    discount: line.discount,
                    uom: line.displayUom,
                    accentColor: AppTheme.primaryIndigo,
                  ),
                )
                .toList(),
            currencySymbol: currencySymbol,
            onEdit: readOnly ? null : onEdit,
            onRemove: readOnly ? null : onRemove,
          ),
      ],
    );
  }
}
