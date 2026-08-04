import 'package:flutter/material.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../../../../ui/core/widgets/line_item_list.dart';

/// Line-items header, empty state, and [LineItemList] for the order editor.
class SalesOrderLineItemsSection extends StatelessWidget {
  final List<OrderLineItem> items;
  final String currencySymbol;
  final bool readOnly;
  final bool hasCustomer;
  final VoidCallback? onAdd;
  final void Function(int index)? onEdit;
  final void Function(int index)? onRemove;

  const SalesOrderLineItemsSection({
    super.key,
    required this.items,
    required this.currencySymbol,
    required this.readOnly,
    required this.hasCustomer,
    this.onAdd,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Line Items',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (!readOnly)
              TextButton.icon(
                onPressed: hasCustomer ? onAdd : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryIndigo,
                ),
              ),
          ],
        ),
        if (items.isEmpty)
          EmptyStateCard(
            icon: Icons.shopping_cart_outlined,
            message: hasCustomer
                ? 'No items added yet'
                : 'Select customer to add items',
          )
        else
          LineItemList(
            items: items
                .map(
                  (line) => LineItemRow(
                    name: line.item.name,
                    sku: line.item.sku,
                    rate: line.rate,
                    taxPercentage: line.taxPercentage.toDouble(),
                    quantity: line.quantity,
                    total: line.total,
                    discount: line.discount,
                    uom: line.displayUom,
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
