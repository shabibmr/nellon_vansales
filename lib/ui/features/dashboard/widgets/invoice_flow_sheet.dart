import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/cubit/list_filter_cubit.dart';
import '../../sales_invoice/bloc/sales_invoice_bloc.dart';

/// Draggable bottom sheet representing the active Invoice Checkout Flow.
///
/// Cart state is owned by the global [SalesInvoiceBloc]. A [ClearCart] event is
/// dispatched when the sheet opens so stale items from the editor or a previous
/// session do not leak in. Checkout success/failure is outcome-driven via
/// [BlocListener] — the sheet does not pop optimistically.
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
                              final cartQty = invoiceState.cart[item] ?? 0;

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
                                              'SKU: ${item.sku} | Rate: $cs${item.rate.toStringAsFixed(2)}',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'In Van Stock: ${item.stock} items',
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
                                      ),
                                      if (cartQty == 0)
                                        ElevatedButton(
                                          onPressed: item.stock == 0
                                              ? null
                                              : () {
                                                  context
                                                      .read<SalesInvoiceBloc>()
                                                      .add(AddToCart(item, 1));
                                                },
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
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                                color: AppTheme.errorRose,
                                              ),
                                              onPressed: () {
                                                final bloc = context
                                                    .read<SalesInvoiceBloc>();
                                                if (cartQty == 1) {
                                                  bloc.add(
                                                      RemoveFromCart(item));
                                                } else {
                                                  bloc.add(UpdateCartQuantity(
                                                    item,
                                                    cartQty - 1,
                                                  ));
                                                }
                                              },
                                            ),
                                            Text(
                                              cartQty.toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                                color: AppTheme.successEmerald,
                                              ),
                                              onPressed: () {
                                                context
                                                    .read<SalesInvoiceBloc>()
                                                    .add(UpdateCartQuantity(
                                                      item,
                                                      cartQty + 1,
                                                    ));
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
                      final sub = line.rate * line.quantity;
                      final tax = sub * (line.taxPercentage / 100);
                      cartSubTotal += sub;
                      cartTaxTotal += tax;
                      cartTotal += sub + tax;
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
                              Text('$cs${cartSubTotal.toStringAsFixed(2)}'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('VAT:', style: TextStyle(fontSize: 13)),
                              Text('$cs${cartTaxTotal.toStringAsFixed(2)}'),
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
                                '$cs${cartTotal.toStringAsFixed(2)}',
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
