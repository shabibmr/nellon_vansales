import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/repositories/invoice_repository.dart';
import '../../../../domain/repositories/item_repository.dart';
import '../../../../domain/repositories/sales_order_repository.dart';
import '../../../../domain/repositories/customer_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../ui/core/cubit/list_filter_cubit.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/utils/quantity_format.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/item_line_editor_dialog.dart';
import '../../sales_invoice/bloc/sales_invoice_editor_bloc.dart';
import '../../sales_invoice/bloc/sales_invoice_editor_event.dart';
import '../../sales_invoice/bloc/sales_invoice_editor_state.dart';

/// Draggable bottom sheet representing the active Invoice Checkout Flow.
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
    final items = context.read<ItemRepository>().getItems();

    return BlocProvider<SalesInvoiceEditorBloc>(
      create: (ctx) => SalesInvoiceEditorBloc(
        invoiceRepository: ctx.read<InvoiceRepository>(),
        salesOrderRepository: ctx.read<SalesOrderRepository>(),
        customerRepository: ctx.read<CustomerRepository>(),
        syncRepository: ctx.read<SyncRepository>(),
        documentNumberService: sl<DocumentNumberService>(),
      )..add(StartNewInvoice(customer: customer)),
      child: BlocProvider<ListFilterCubit<Item>>(
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
  String? _resolvingItemId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  InvoiceLineItem? _lineForItem(
    SalesInvoiceEditorState state,
    Item item,
  ) {
    for (final line in state.editingItems) {
      if (line.item.id == item.id) return line;
    }
    return null;
  }

  Future<void> _addOrEditItem(Item item, {InvoiceLineItem? existing}) async {
    if (_resolvingItemId != null) return;

    Item resolved = item;
    var offlineFallback = false;

    if (existing == null) {
      setState(() => _resolvingItemId = item.id);
      try {
        final result =
            await context.read<ItemRepository>().resolveItemUnitConversions(item);
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
      resolved = existing.item.unitConversions.isNotEmpty
          ? existing.item
          : item;
      if (resolved.unitConversions.isEmpty) {
        setState(() => _resolvingItemId = item.id);
        try {
          final result =
              await context.read<ItemRepository>().resolveItemUnitConversions(resolved);
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
        context.read<SalesInvoiceEditorBloc>().add(RemoveLineItem(resolved));
      }
      return;
    }

    context.read<SalesInvoiceEditorBloc>().add(
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

    return BlocConsumer<SalesInvoiceEditorBloc, SalesInvoiceEditorState>(
      listenWhen: (prev, curr) =>
          prev.errorMessage != curr.errorMessage ||
          prev.successMessage != curr.successMessage,
      listener: (context, state) {
        if (state.successMessage != null) {
          showSuccessSnackBar(context, state.successMessage!);
          context
              .read<SalesInvoiceEditorBloc>()
              .add(const ClearSalesInvoiceEditorMessages());
          Navigator.pop(context);
          widget.onInvoiceSubmitted();
        } else if (state.errorMessage != null) {
          showErrorSnackBar(context, state.errorMessage!);
          context
              .read<SalesInvoiceEditorBloc>()
              .add(const ClearSalesInvoiceEditorMessages());
        }
      },
      builder: (context, invoiceState) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? AppTheme.darkBackground
                    : AppTheme.lightBackground,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                        child: const Icon(Icons.receipt_long, color: AppTheme.primaryIndigo),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.customer.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Direct Van Sale',
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search items to add...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                context.read<ListFilterCubit<Item>>().setQuery('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (query) => context.read<ListFilterCubit<Item>>().setQuery(query),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: BlocBuilder<ListFilterCubit<Item>, ListFilterState<Item>>(
                      builder: (context, filterState) {
                        final items = filterState.filteredItems;
                        if (items.isEmpty) {
                          return const Center(child: Text('No items match search.'));
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final line = _lineForItem(invoiceState, item);
                            final isResolving = _resolvingItemId == item.id;

                            return ListTile(
                              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'SKU: ${item.sku} • Stock: ${formatQuantity(item.stock)} ${item.uom} • ${formatCurrency(item.rate, cs)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: isResolving
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (line != null) ...[
                                          Text(
                                            '${formatQuantity(line.quantity)} ${line.displayUom} (${formatCurrency(line.total, cs)})',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryIndigo,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        IconButton(
                                          icon: Icon(
                                            line != null ? Icons.edit : Icons.add_circle_outline,
                                            color: AppTheme.primaryIndigo,
                                          ),
                                          onPressed: () => _addOrEditItem(item, existing: line),
                                        ),
                                        if (line != null)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                                            onPressed: () {
                                              context.read<SalesInvoiceEditorBloc>().add(RemoveLineItem(item));
                                            },
                                          ),
                                      ],
                                    ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        double cartSubTotal = 0.0;
                        double cartTaxTotal = 0.0;
                        double cartTotal = 0.0;

                        for (final line in invoiceState.editingItems) {
                          cartSubTotal += line.subTotal;
                          cartTaxTotal += line.taxAmount;
                          cartTotal += line.total;
                        }

                        final canSubmit = invoiceState.editingItems.isNotEmpty && !invoiceState.isSaving;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sub Total:', style: TextStyle(fontSize: 13)),
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
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                                      context.read<SalesInvoiceEditorBloc>().add(
                                            const SaveInvoice(notes: 'Van Sales Checkout'),
                                          );
                                    }
                                  : null,
                              child: invoiceState.isSaving
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
