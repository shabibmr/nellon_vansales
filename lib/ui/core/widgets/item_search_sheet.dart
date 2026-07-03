import 'package:flutter/material.dart';
import '../../../domain/models/item.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';

/// Generic item-search bottom sheet shared by sales order, invoice, and return flows.
///
/// The caller provides the pre-filtered [items] list and handles flow-specific
/// follow-up dialogs via [onSelected].
class ItemSearchSheet extends StatefulWidget {
  final List<Item> items;
  final String title;
  final String emptyMessage;
  final Color accentColor;
  final Future<void> Function(Item item, BuildContext sheetContext) onSelected;

  const ItemSearchSheet({
    super.key,
    required this.items,
    required this.title,
    required this.emptyMessage,
    required this.onSelected,
    this.accentColor = AppTheme.primaryIndigo,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required List<Item> items,
    required String title,
    required String emptyMessage,
    required Future<void> Function(Item item, BuildContext sheetContext)
    onSelected,
    Color accentColor = AppTheme.primaryIndigo,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ItemSearchSheet(
        items: items,
        title: title,
        emptyMessage: emptyMessage,
        onSelected: onSelected,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<ItemSearchSheet> createState() => _ItemSearchSheetState();
}

class _ItemSearchSheetState extends State<ItemSearchSheet> {
  late List<Item> _filtered;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  void _onSearch(String query) {
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _filtered = widget.items;
      } else {
        final q = query.toLowerCase();
        _filtered = widget.items.where((item) {
          return item.name.toLowerCase().contains(q) ||
              item.sku.toLowerCase().contains(q);
        }).toList();
      }
    });
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
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                autofocus: true,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search items by name or SKU...',
                  prefixIcon: Icon(Icons.search, color: widget.accentColor),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? widget.emptyMessage
                                : 'No items match your search',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _filtered[index];
                        return ListTile(
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'SKU: ${item.sku} | Rate: ${formatCurrency(item.rate, cs)}',
                          ),
                          trailing: item.stock >= 0
                              ? Text(
                                  'Stock: ${item.stock}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: item.stock > 0
                                        ? AppTheme.successEmerald
                                        : AppTheme.errorRose,
                                  ),
                                )
                              : null,
                          onTap: () => widget.onSelected(item, context),
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
