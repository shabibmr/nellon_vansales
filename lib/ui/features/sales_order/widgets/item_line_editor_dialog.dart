import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/widgets/item_line_editor_dialog.dart';

/// Order line editor — no stock limit enforced (forward order delivery).
class ItemOrderLineEditorDialog extends StatelessWidget {
  final Item item;
  final int initialQuantity;
  final int originalQuantity;
  final double? initialRate;
  final double? initialDiscount;

  const ItemOrderLineEditorDialog({
    super.key,
    required this.item,
    this.initialQuantity = 0,
    this.originalQuantity = 0,
    this.initialRate,
    this.initialDiscount,
  });

  @override
  Widget build(BuildContext context) {
    return SharedItemLineEditorDialog(
      item: item,
      initialQuantity: initialQuantity,
      originalQuantity: originalQuantity,
      allowUnlimitedQuantity: true,
      title: 'Order Line Item Details',
      initialRate: initialRate,
      initialDiscount: initialDiscount,
    );
  }
}
