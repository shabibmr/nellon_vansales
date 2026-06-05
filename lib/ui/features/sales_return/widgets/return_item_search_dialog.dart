import 'package:flutter/material.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import 'return_invoice_selector_dialog.dart';

/// Modal dialog for searching van inventory items to add to a sales return.
class ReturnItemSearchDialog extends StatefulWidget {
  final String customerId;
  final List<String> excludedItemIds;

  const ReturnItemSearchDialog({
    super.key,
    required this.customerId,
    this.excludedItemIds = const [],
  });

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
                  'Select Return Item',
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
                prefixIcon: Icon(Icons.search, color: AppTheme.warningAmber),
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
