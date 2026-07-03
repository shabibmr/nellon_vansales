import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/widgets/item_search_sheet.dart';
import 'item_line_editor_dialog.dart';

/// Invoice item search — delegates UI to [ItemSearchSheet].
/// Returns the selected item + confirmed quantity.
class ItemSearchDialog {
  static Future<(Item, int, double, double)?> show(
    BuildContext context, {
    List<String> excludedItemIds = const [],
  }) async {
    final db = sl<HiveDatabaseService>();
    final items = db.getItems().where((item) => !excludedItemIds.contains(item.id)).toList();

    (Item, int, double, double)? result;

    await ItemSearchSheet.show<void>(
      context,
      items: items,
      title: 'Search Van Inventory',
      emptyMessage: 'No items in van stock',
      onSelected: (item, sheetContext) async {
        final editorResult = await showDialog<(int, double, double)>(
          context: sheetContext,
          builder: (context) => ItemLineEditorDialog(item: item),
        );
        if (editorResult != null) {
          final (qty, rate, discount) = editorResult;
          if (qty > 0) {
            result = (item, qty, rate, discount);
            if (sheetContext.mounted) Navigator.pop(sheetContext, null);
          }
        }
      },
    );

    return result;
  }
}
