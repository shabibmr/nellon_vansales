import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/utils/quantity_format.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/cubit/list_filter_cubit.dart';
import '../../../../ui/core/widgets/item_line_editor_dialog.dart';
import '../../sales_invoice/bloc/sales_invoice_bloc.dart';

/// Draggable bottom sheet representing the active Invoice Checkout Flow.
///
/// Cart state is owned by the global [SalesInvoiceBloc]. A [ClearCart] event is
/// dispatched when the sheet opens so stale items from the editor or a previous
/// session do not leak in. Checkout success/failure is outcome-driven via
/// [BlocListener] — the sheet does not pop optimistically.
///
/// Item add/edit uses the same multi-UOM path as the full invoice editor:
/// resolve conversions → [SharedItemLineEditorDialog] → [AddOrUpdateLineItem].
class InvoiceFlowSheet extends StatelessWidget {
  final Customer customer;
  final bool isDark;
  final VoidCallback onInvoiceSubmitted;

  const InvoiceFlowSheet({
    super.key,
    required this.customer,
    required this.isDark,
    required this.onInvoiceSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final items = sl<HiveDatabaseService>().getItems();

    return BlocProvider<ListFilterCubit<Item>>(
      create: (_) => ListFilterCubit<Item>(
        initialItems: items,
        filterPredicate: (item, query) {
          final q = query.toLowerCase();
          return item.name.toLowerCase().contains(q) ||
              item.sku.toLowerCase().contains(q);
        },
      ),
      child: _InvoiceFlowSheetBody(
        customer: customer,
        isDark: isDark,
        onInvoiceSubmitted: onInvoiceSubmitted,
      ),
    );
  }
}

class _InvoiceFlowSheetBody extends StatefulWidget {
  final Customer customer;
  final bool isDark;
  final VoidCallback onInvoiceSubmitted;

  const _InvoiceFlowSheetBody({
    required this.customer,
    required this.isDark,
    required this.onInvoiceSubmitted,
  });

  @override
  State<_InvoiceFlowSheetBody> createState() => _InvoiceFlowSheetBodyState();
}

class _InvoiceFlowSheetBodyState extends State<_InvoiceFlowSheetBody> {
  final TextEditingController _searchController = TextEditingController();

  /// Item id currently resolving multi-UOM (shows a spinner on that row).
  String? _resolvingItemId;

  @override
  void initState() {
    super.initState();
    // Prevent stale cart items from a previous checkout / editor session.
    context.read<SalesInvoiceBloc>().add(ClearCart());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  InvoiceLineItem? _lineForItem(
    SalesInvoiceState state,
    Item item,
  ) {
    for (final line in state.editingItems) {
      if (line.item.id == item.id) return line;
    }
    return null;
  }

  /// Resolve multi-UOM, open the shared line editor, then upsert the cart line.
  Future<void> _addOrEditItem(Item item, {InvoiceLineItem? existing}) async {
    if (_resolvingItemId != null) return;

    Item resolved = item;
    var offlineFallback = false;

    if (existing == null) {
      setState(() => _resolvingItemId = item.id);
      try {
        final result =
            await sl<SalesRepository>().resolveItemUnitConversions(item);
        resolved = result.item;
        offlineFallback = result.offlineFallback;
      } finally {
        if (mounted) setState(() => _resolvingItemId = null);
      }
      if (!mounted) return;
      if (offlineFallback) {
        showErrorSnackBar(
          context,
          "Couldn't load other units — using base unit.",
        );
      }
    } else {
      // Prefer conversions already on the line's item snapshot.
      resolved = existing.item.unitConversions.isNotEmpty
          ? existing.item
          : item;
      if (resolved.unitConversions.isEmpty) {
        setState(() => _resolvingItemId = item.id);
        try {
          final result =
              await sl<SalesRepository>().resolveItemUnitConversions(resolved);
          resolved = result.item;
          offlineFallback = result.offlineFallback;
        } finally {
          if (mounted) setState(() => _resolvingItemId = null);
        }
        if (!mounted) return;
        if (offlineFallback) {
          showErrorSnackBar(
            context,
            "Couldn't load other units — using base unit.",
          );
        }
      }
    }

    if (!mounted) return;

    final result = await showDialog<ItemLineEditorResult>(
      context: context,
      builder: (context) => SharedItemLineEditorDialog(
        item: resolved,
        initialQuantity: existing?.quantity ?? 0,
        originalQuantity: existing?.quantityInBase ?? 0,
        initialRate: existing?.rate,
        initialDiscount: existing?.discount,
        initialUom: existing?.displayUom,
      ),
    );

    if (result == null || !mounted) return;
    if (result.quantity <= 0) {
      if (existing != null) {
        context.read<SalesInvoiceBloc>().add(RemoveLineItem(resolved));
      }
      return;
    }

    context.read<SalesInvoiceBloc>().add(
          AddOrUpdateLineItem(
            item: resolved,
            quantity: result.quantity,
            rate: result.rate,
            discount: result.discount,
            uom: result.uom,
            unitConversionId: result.unitConversionId,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return MultiBlocListener(
      listeners: [
        BlocListener<SalesInvoiceBloc, SalesInvoiceState>(
          listenWhen: (prev, curr) =>
              prev.errorMessage != curr.errorMessage &&
              curr.errorMessage != null,
          listener: (context, state) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<SalesInvoiceBloc>().add(ClearMessages());
          },
        ),
        BlocListener<SalesInvoiceBloc, SalesInvoiceState>(
          listenWhen: (prev, curr) =>
              prev.successMessage != curr.successMessage &&
              curr.successMessage != null,
          listener: (context, state) {
            final message = state.successMessage!;
            context.read<SalesInvoiceBloc>().add(ClearMessages());
            Navigator.pop(context);
            showSuccessSnackBar(context, message);
            widget.onInvoiceSubmitted();
          },
        ),
      ],
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New Invoice: ${widget.customer.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                BlocBuilder<ListFilterCubit<Item>, ListFilterState<Item>>(
                  buildWhen: (prev, curr) => prev.query != curr.query,
                  builder: (context, filterState) {
                    return TextField(
                      controller: _searchController,
                      onChanged: (value) => context
                          .read<ListFilterCubit<Item>>()
                          .setQuery(value),
                      decoration: InputDecoration(
                        hintText: 'Search items by name or SKU...',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.primaryIndigo,
                        ),
                        suffixIcon: filterState.query.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.cancel,
                                  size: 20,
                                  color: widget.isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  context
                                      .read<ListFilterCubit<Item>>()
                                      .setQuery('');
                                },
                              )
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
                    buildWhen: (prev, curr) =>
                        prev.editingItems != curr.editingItems,
                    builder: (context, invoiceState) {
                      return BlocBuilder<ListFilterCubit<Item>,
                          ListFilterState<Item>>(
                        builder: (context, filterState) {
                          final visible = filterState.filteredItems;

                          if (visible.isEmpty) {
                            return Center(
                              child: Text(
                                filterState.query.isEmpty
                                    ? 'No items in van stock'
                                    : 'No items match "${filterState.query}"',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            controller: scrollController,
                            itemCount: visible.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              final line = _lineForItem(invoiceState, item);
                              final isResolving = _resolvingItemId == item.id;

                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            Text(
                                              'SKU: ${item.sku} | Rate: $cs${item.rate.toStringAsFixed(2)}'
                                              '${item.uom.isNotEmpty ? ' / ${item.uom}' : ''}',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'In Van Stock: ${formatQuantity(item.stock)}'
                                              '${item.uom.isNotEmpty ? ' ${item.uom}' : ''}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: item.stock > 0
                                                    ? AppTheme.successEmerald
                                                    : AppTheme.errorRose,
                                              ),
                                            ),
                                            if (line != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'In cart: ${formatQuantity(line.quantity)}'
                                                '${line.displayUom.isNotEmpty ? ' ${line.displayUom}' : ''}'
                                                ' · ${formatCurrency(line.total, cs)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.primaryIndigo,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (isResolving)
                                        const SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: Padding(
                                            padding: EdgeInsets.all(8),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      else if (line == null)
                                        ElevatedButton(
                                          onPressed: item.stock == 0
                                              ? null
                                              : () => _addOrEditItem(item),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                          ),
                                          child: const Text('ADD'),
                                        )
                                      else
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextButton(
                                              onPressed: () => _addOrEditItem(
                                                item,
                                                existing: line,
                                              ),
                                              child: const Text('EDIT'),
                                            ),
                                            IconButton(
                                              tooltip: 'Remove',
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                                color: AppTheme.errorRose,
                                              ),
                                              onPressed: () {
                                                context
                                                    .read<SalesInvoiceBloc>()
                                                    .add(RemoveLineItem(item));
                                              },
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
                  buildWhen: (prev, curr) =>
                      prev.editingItems != curr.editingItems ||
                      prev.isLoading != curr.isLoading,
                  builder: (context, invoiceState) {
                    double cartSubTotal = 0.0;
                    double cartTaxTotal = 0.0;
                    double cartTotal = 0.0;

                    for (final line in invoiceState.editingItems) {
                      cartSubTotal += line.subTotal;
                      cartTaxTotal += line.taxAmount;
                      cartTotal += line.total;
                    }

                    final canSubmit = invoiceState.editingItems.isNotEmpty &&
                        !invoiceState.isLoading;

                    return Container(
                      padding: const EdgeInsets.only(top: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: widget.isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Sub Total:',
                                style: TextStyle(fontSize: 13),
                              ),
                              Text(formatCurrency(cartSubTotal, cs)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('VAT:', style: TextStyle(fontSize: 13)),
                              Text(formatCurrency(cartTaxTotal, cs)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Invoice Total:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                formatCurrency(cartTotal, cs),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: AppTheme.primaryIndigo,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: canSubmit
                                ? () {
                                    context.read<SalesInvoiceBloc>().add(
                                          CheckoutRequested(
                                            customer: widget.customer,
                                            notes: 'Van Sales Checkout',
                                          ),
                                        );
                                  }
                                : null,
                            child: invoiceState.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'SUBMIT SALES INVOICE'
                                    '${cartTotal > 0 ? ' (${formatCurrency(cartTotal, cs)})' : ''}',
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
