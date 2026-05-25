import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import 'item_line_editor_dialog.dart';

/// Modal dialog that allows searching for inventory items in van stock.
///
/// Selecting an item opens the [ItemLineEditorDialog] to capture the desired quantity.
class ItemSearchDialog extends StatefulWidget {
  final List<String> excludedItemIds; // Do not show items already present in the invoice

  const ItemSearchDialog({super.key, this.excludedItemIds = const []});

  @override
  State<ItemSearchDialog> createState() => _ItemSearchDialogState();
}

class _ItemSearchDialogState extends State<ItemSearchDialog> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  late List<Item> _allItems;
  List<Item> _filteredItems = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Retrieve all items and filter out excluded ones
    _allItems = _db.getItems()
        .where((item) => !widget.excludedItemIds.contains(item.id))
        .toList();
    _filteredItems = _allItems;
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = _allItems;
      } else {
        _filteredItems = _allItems.where((item) {
          final queryLower = query.toLowerCase();
          return item.name.toLowerCase().contains(queryLower) ||
              item.sku.toLowerCase().contains(queryLower);
        }).toList();
      }
    });
  }

  Future<void> _selectItem(Item item) async {
    final qty = await showDialog<int>(
      context: context,
      builder: (context) => ItemLineEditorDialog(item: item),
    );

    if (qty != null && qty > 0) {
      if (mounted) {
        Navigator.pop(context, MapEntry(item, qty));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Search Van Inventory',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search items by name or SKU...',
                prefixIcon: Icon(Icons.search, color: AppTheme.primaryIndigo),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty ? 'No items in van stock' : 'No items match your search',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredItems.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];

                        return Card(
                          margin: EdgeInsets.zero,
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          child: InkWell(
                            onTap: () => _selectItem(item),
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
                                          item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'SKU: ${item.sku} | Rate: $cs${item.rate.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Stock: ${item.stock}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: item.stock > 0
                                              ? AppTheme.successEmerald
                                              : AppTheme.errorRose,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
