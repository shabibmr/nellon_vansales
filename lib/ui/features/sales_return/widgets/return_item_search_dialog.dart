import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import 'return_invoice_selector_dialog.dart';

/// Bottom sheet for searching van inventory items to add to a sales return.
class ReturnItemSearchDialog extends StatefulWidget {
  final String customerId;
  final List<String> excludedItemIds;

  const ReturnItemSearchDialog({
    super.key,
    required this.customerId,
    this.excludedItemIds = const [],
  });

  /// Presents the return item search as a modal bottom sheet, matching the
  /// customer selector styling. Returns the selected return line items.
  static Future<List<SalesReturnLineItem>?> show(
    BuildContext context, {
    required String customerId,
    List<String> excludedItemIds = const [],
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<List<SalesReturnLineItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ReturnItemSearchDialog(
        customerId: customerId,
        excludedItemIds: excludedItemIds,
      ),
    );
  }

  @override
  State<ReturnItemSearchDialog> createState() => _ReturnItemSearchDialogState();
}

class _ReturnItemSearchDialogState extends State<ReturnItemSearchDialog> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  late List<Item> _allItems;
  List<Item> _filteredItems = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Get all local invoices for this customer
    final invoices = _db.getLocalInvoices()
        .where((inv) => inv.customerId == widget.customerId)
        .toList();
    // Get all unique item IDs from these invoices
    final purchasedItemIds = invoices
        .expand((inv) => inv.items)
        .map((line) => line.item.id)
        .toSet();

    _allItems = _db.getItems()
        .where((item) => purchasedItemIds.contains(item.id))
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
          final q = query.toLowerCase();
          return item.name.toLowerCase().contains(q) || item.sku.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Future<void> _selectItem(Item item) async {
    final customer = _db.getCustomers().firstWhere((c) => c.id == widget.customerId);
    final result = await showDialog<List<SalesReturnLineItem>>(
      context: context,
      builder: (context) => ReturnInvoiceSelectorDialog(
        customer: customer,
        item: item,
        currentLines: const [],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      Navigator.pop(context, result);
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
              'Select Return Item',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search items by name or SKU...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.warningAmber),
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
