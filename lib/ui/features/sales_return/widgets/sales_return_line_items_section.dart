import 'package:flutter/material.dart';

import '../../../../domain/models/sales_return.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/line_item_list.dart';

class SalesReturnLineItemsSection extends StatelessWidget {
  final List<SalesReturnLineItem> items;
  final String currencySymbol;
  final bool readOnly;
  final bool hasCustomer;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  const SalesReturnLineItemsSection({
    super.key,
    required this.items,
    required this.currencySymbol,
    required this.readOnly,
    required this.hasCustomer,
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
              'RETURN ITEMS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (!readOnly)
              TextButton.icon(
                onPressed: hasCustomer ? onAdd : null,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('ADD RETURN ITEM'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.assignment_return_outlined,
            title: 'No Return Items',
            message: readOnly
                ? 'This sales return has no items.'
                : hasCustomer
                    ? 'Tap "ADD RETURN ITEM" to select items from previous customer invoices.'
                    : 'Select a customer first to add return items.',
          )
        else
          LineItemList(
            items: items
                .map(
                  (line) => LineItemRow(
                    name: line.invoiceLineItem.item.name,
                    sku: line.invoiceLineItem.item.sku,
                    rate: line.invoiceLineItem.rate,
                    taxPercentage: line.invoiceLineItem.taxPercentage,
                    quantity: line.returnedQuantity,
                    total: line.total,
                    discount: line.invoiceLineItem.discount,
                    uom: line.invoiceLineItem.displayUom,
                    accentColor: AppTheme.warningAmber,
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
