import 'package:flutter/material.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/widgets/item_search_sheet.dart';
import 'return_invoice_selector_dialog.dart';

/// Return item search — delegates UI to [ItemSearchSheet].
/// Filters to items the customer has actually purchased.
class ReturnItemSearchDialog {
  static Future<List<SalesReturnLineItem>?> show(
    BuildContext context, {
    required String customerId,
    List<String> excludedItemIds = const [],
  }) async {
    final db = sl<HiveDatabaseService>();

    final invoices = db.getLocalInvoices().where((inv) => inv.customerId == customerId).toList();
    final purchasedItemIds = invoices.expand((inv) => inv.items).map((line) => line.item.id).toSet();

    final items = db
        .getItems()
        .where((item) => purchasedItemIds.contains(item.id))
        .where((item) => !excludedItemIds.contains(item.id))
        .toList();

    List<SalesReturnLineItem>? result;

    await ItemSearchSheet.show<void>(
      context,
      items: items,
      title: 'Select Return Item',
      emptyMessage: 'No items found for this customer',
      accentColor: AppTheme.warningAmber,
      onSelected: (item, sheetContext) async {
        final customer = db.getCustomers().firstWhere((c) => c.id == customerId);
        final lines = await showDialog<List<SalesReturnLineItem>>(
          context: sheetContext,
          builder: (context) => ReturnInvoiceSelectorDialog(
            customer: customer,
            item: item,
            currentLines: const [],
          ),
        );
        if (lines != null && lines.isNotEmpty) {
          result = lines;
          if (sheetContext.mounted) Navigator.pop(sheetContext, null);
        }
      },
    );

    return result;
  }
}
