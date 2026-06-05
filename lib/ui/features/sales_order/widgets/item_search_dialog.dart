import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import 'item_line_editor_dialog.dart';

/// Bottom sheet that allows searching for inventory items in van stock for a Sales Order.
///
/// Selecting an item opens the [ItemOrderLineEditorDialog] to capture the desired quantity.
class ItemOrderSearchDialog extends StatefulWidget {
  final List<String> excludedItemIds;

  const ItemOrderSearchDialog({super.key, this.excludedItemIds = const []});

  /// Presents the item search as a modal bottom sheet, matching the
  /// customer selector styling. Returns the selected item and quantity.
  static Future<MapEntry<Item, int>?> show(
    BuildContext context, {
    List<String> excludedItemIds = const [],
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<MapEntry<Item, int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ItemOrderSearchDialog(excludedItemIds: excludedItemIds),
    );
  }

  @override
  State<ItemOrderSearchDialog> createState() => _ItemOrderSearchDialogState();
}

class _ItemOrderSearchDialogState extends State<ItemOrderSearchDialog> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  late List<Item> _allItems;
  List<Item> _filteredItems = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
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
      builder: (context) => ItemOrderLineEditorDialog(item: item),
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

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Search Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search items by name or SKU...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryIndigo),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const Divider(),
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
                      controller: scrollController,
                      itemCount: _filteredItems.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        return ListTile(
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('SKU: ${item.sku} | Rate: $cs${item.rate.toStringAsFixed(2)}'),
                          trailing: Text(
                            'Stock: ${item.stock}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: item.stock > 0
                                  ? AppTheme.successEmerald
                                  : AppTheme.errorRose,
                            ),
                          ),
                          onTap: () => _selectItem(item),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
