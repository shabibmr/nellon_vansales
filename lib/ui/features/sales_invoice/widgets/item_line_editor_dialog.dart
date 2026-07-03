import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/widgets/item_line_editor_dialog.dart';

/// Invoice line editor — enforces stock limit via [SharedItemLineEditorDialog].
class ItemLineEditorDialog extends StatelessWidget {
  final Item item;
  final int initialQuantity;
  final int originalQuantity;
  final double? initialRate;
  final double? initialDiscount;

  const ItemLineEditorDialog({
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
      allowUnlimitedQuantity: false,
      title: 'Line Item Details',
      initialRate: initialRate,
      initialDiscount: initialDiscount,
    );
  }
}
