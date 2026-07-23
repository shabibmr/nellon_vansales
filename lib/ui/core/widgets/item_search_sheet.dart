import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/injection.dart';
import '../../../domain/models/item.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../theme/app_theme.dart';
import '../extensions/org_context_extension.dart';
import '../utils/currency.dart';
import '../cubit/list_filter_cubit.dart';

/// Generic item-search bottom sheet shared by sales order, invoice, and return flows.
///
/// The caller provides the pre-filtered [items] list and handles flow-specific
/// follow-up dialogs via [onSelected].
class ItemSearchSheet extends StatelessWidget {
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
    required Future<void> Function(Item item, BuildContext sheetContext) onSelected,
    Color accentColor = AppTheme.primaryIndigo,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => BlocProvider<ListFilterCubit<Item>>(
        create: (_) => ListFilterCubit<Item>(
          initialItems: items,
          filterPredicate: (item, query) {
            final q = query.toLowerCase();
            return item.name.toLowerCase().contains(q) ||
                item.sku.toLowerCase().contains(q);
          },
        ),
        child: ItemSearchSheet(
          items: items,
          title: title,
          emptyMessage: emptyMessage,
          onSelected: onSelected,
          accentColor: accentColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ItemSearchSheetBody(
      title: title,
      emptyMessage: emptyMessage,
      onSelected: onSelected,
      accentColor: accentColor,
    );
  }
}

class _ItemSearchSheetBody extends StatefulWidget {
  final String title;
  final String emptyMessage;
  final Color accentColor;
  final Future<void> Function(Item item, BuildContext sheetContext) onSelected;

  const _ItemSearchSheetBody({
    required this.title,
    required this.emptyMessage,
    required this.onSelected,
    required this.accentColor,
  });

  @override
  State<_ItemSearchSheetBody> createState() => _ItemSearchSheetBodyState();
}

class _ItemSearchSheetBodyState extends State<_ItemSearchSheetBody> {
  final _searchController = TextEditingController();

  /// Id of the item whose multi-UOM is being fetched, or null when idle.
  /// Drives the per-tile spinner and blocks concurrent taps.
  String? _resolvingItemId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Resolves the tapped item's multi-UOM (cached or `GET /items/{id}`) before
  /// handing it to the caller, so the line editor opens with full unit options.
  Future<void> _handleTap(Item item, BuildContext sheetContext) async {
    if (_resolvingItemId != null) return;
    setState(() => _resolvingItemId = item.id);
    Item resolved = item;
    try {
      resolved = await sl<SalesRepository>().resolveItemUnitConversions(item);
    } finally {
      if (mounted) setState(() => _resolvingItemId = null);
    }
    if (!sheetContext.mounted) return;
    await widget.onSelected(resolved, sheetContext);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    // Lift the sheet above the soft keyboard so the search field stays at the
    // top and the results list remains visible (not covered mid-sheet).
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.95,
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
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (val) =>
                      context.read<ListFilterCubit<Item>>().setQuery(val),
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
              const Divider(height: 1),
              Expanded(
                child: BlocBuilder<ListFilterCubit<Item>, ListFilterState<Item>>(
                  builder: (context, state) {
                    final filtered = state.filteredItems;

                    if (filtered.isEmpty) {
                      return Center(
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
                              state.query.isEmpty
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
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isResolving = _resolvingItemId == item.id;
                        return ListTile(
                          enabled: _resolvingItemId == null,
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'SKU: ${item.sku} | Rate: ${formatCurrency(item.rate, cs)}',
                          ),
                          trailing: isResolving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : item.stock >= 0
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
                          onTap: () => _handleTap(item, context),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
