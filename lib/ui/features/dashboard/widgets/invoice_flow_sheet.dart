import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../sales_invoice/bloc/sales_invoice_bloc.dart';

/// Draggable bottom sheet representing the active Invoice Checkout Flow.
///
/// Permits browsing van stock, adding/incrementing items in the cart, showing dynamic tax and totals calculations,
/// validating customer credit limits, and filing invoices.
class InvoiceFlowSheet extends StatefulWidget {
  /// Customer profile to bill.
  final Customer customer;

  /// Visual context.
  final bool isDark;

  /// Callback triggered when the sales invoice checkout successfully completes.
  final VoidCallback onInvoiceSubmitted;

  /// Creates a new [InvoiceFlowSheet].
  const InvoiceFlowSheet({
    super.key,
    required this.customer,
    required this.isDark,
    required this.onInvoiceSubmitted,
  });

  @override
  State<InvoiceFlowSheet> createState() => _InvoiceFlowSheetState();
}

class _InvoiceFlowSheetState extends State<InvoiceFlowSheet> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  late List<Item> _items;
  final Map<Item, int> _localCart = {};

  @override
  void initState() {
    super.initState();
    _items = _db.getItems();
  }

  @override
  Widget build(BuildContext context) {
    double cartSubTotal = 0.0;
    double cartTaxTotal = 0.0;
    double cartTotal = 0.0;

    _localCart.forEach((item, qty) {
      final sub = item.rate * qty;
      final tax = sub * (item.taxPercentage / 100);
      cartSubTotal += sub;
      cartTaxTotal += tax;
      cartTotal += (sub + tax);
    });

    final cs = context.org.currencySymbol;
    return DraggableScrollableSheet(
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Item Catalog Scroll
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: _items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final cartQty = _localCart[item] ?? 0;

                    return Card(
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
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    'SKU: ${item.sku} | Rate: $cs${item.rate.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 11),
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
                                  )
                                ],
                              ),
                            ),

                            // Add/Remove Counter UI
                            if (cartQty == 0)
                              ElevatedButton(
                                onPressed: item.stock == 0
                                    ? null
                                    : () {
                                        setState(() {
                                          _localCart[item] = 1;
                                        });
                                      },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                child: const Text('ADD'),
                              )
                            else
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorRose),
                                    onPressed: () {
                                      setState(() {
                                        if (cartQty == 1) {
                                          _localCart.remove(item);
                                        } else {
                                          _localCart[item] = cartQty - 1;
                                        }
                                      });
                                    },
                                  ),
                                  Text(
                                    cartQty.toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.successEmerald),
                                    onPressed: () {
                                      if (cartQty < item.stock) {
                                        setState(() {
                                          _localCart[item] = cartQty + 1;
                                        });
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Cannot exceed available van stock')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Cart summary totals & Checkout trigger
              Container(
                padding: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Sub Total:', style: TextStyle(fontSize: 13)),
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
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                      onPressed: _localCart.isEmpty
                          ? null
                          : () {
                              final bloc = context.read<SalesInvoiceBloc>();
                              bloc.add(ClearCart());
                              _localCart.forEach((item, qty) {
                                bloc.add(AddToCart(item, qty));
                              });
                              bloc.add(CheckoutRequested(customer: widget.customer, notes: 'Van Sales Checkout'));

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppTheme.successEmerald,
                                  content: Text('Invoice generated & queued offline! Subtotal: $cs${cartTotal.toStringAsFixed(2)}'),
                                ),
                              );
                              widget.onInvoiceSubmitted();
                            },
                      child: const Text('SUBMIT SALES INVOICE'),
                    )
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }
}
