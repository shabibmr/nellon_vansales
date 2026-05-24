import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../bloc/sales_invoice_bloc.dart';
import '../widgets/item_line_editor_dialog.dart';
import '../widgets/item_search_dialog.dart';

/// Screen enabling Creation or Editing of a Sales Invoice.
///
/// Features:
/// 1. Invoice Date Picker.
/// 2. Customer Selector modal.
/// 3. Dynamic multi-line items list.
/// 4. Tap-to-adjust or swipe-to-delete line items.
/// 5. Live pricing summary (Subtotal, GST, Total).
/// 6. Save trigger with automatic van stock reconciliation.
class SalesInvoiceEditorPage extends StatefulWidget {
  const SalesInvoiceEditorPage({super.key});

  @override
  State<SalesInvoiceEditorPage> createState() => _SalesInvoiceEditorPageState();
}

class _SalesInvoiceEditorPageState extends State<SalesInvoiceEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  late TextEditingController _notesController;
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  @override
  void initState() {
    super.initState();
    final blocState = context.read<SalesInvoiceBloc>().state;
    _notesController = TextEditingController(text: blocState.editingNotes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectInvoiceDate(DateTime currentDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primaryIndigo,
                    onPrimary: Colors.white,
                    surface: AppTheme.darkSurface,
                    onSurface: AppTheme.darkText,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.primaryIndigo,
                    onPrimary: Colors.white,
                    surface: AppTheme.lightSurface,
                    onSurface: AppTheme.lightText,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      context.read<SalesInvoiceBloc>().add(UpdateInvoiceDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final allCustomers = _db.getCustomers()..sort((a, b) => a.name.compareTo(b.name));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        var filtered = allCustomers;
        final searchController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setModalState) {
            void onSearch(String query) {
              final q = query.toLowerCase();
              setModalState(() {
                filtered = q.isEmpty
                    ? allCustomers
                    : allCustomers.where((c) {
                        return c.name.toLowerCase().contains(q) ||
                            c.companyName.toLowerCase().contains(q) ||
                            c.phone.contains(query);
                      }).toList();
              });
            }

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
                      'Select Customer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: onSearch,
                        decoration: InputDecoration(
                          hintText: 'Search by name, company or phone...',
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
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No customers found',
                                style: TextStyle(
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final customer = filtered[index];
                                return ListTile(
                                  title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(customer.companyName),
                                  trailing: customer.outstandingBalance > 0
                                      ? Text(
                                          'Outstanding: ₹${customer.outstandingBalance.toStringAsFixed(2)}',
                                          style: const TextStyle(color: AppTheme.errorRose, fontSize: 11, fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                  onTap: () {
                                    this.context.read<SalesInvoiceBloc>().add(UpdateInvoiceCustomer(customer));
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openItemSearch(List<InvoiceLineItem> editingItems) async {
    final excludedIds = editingItems.map((line) => line.item.id).toList();
    final result = await showDialog<MapEntry<Item, int>>(
      context: context,
      builder: (context) => ItemSearchDialog(excludedItemIds: excludedIds),
    );

    if (result != null && mounted) {
      context.read<SalesInvoiceBloc>().add(AddOrUpdateLineItem(
            item: result.key,
            quantity: result.value,
          ));
    }
  }

  Future<void> _editLineItem(
    InvoiceLineItem lineItem,
    bool isEditingNew,
    String? editingInvoiceId,
    List<SalesInvoice> invoices,
  ) async {
    // Determine if there was an original quantity in the original saved invoice
    int originalQty = 0;
    if (!isEditingNew && editingInvoiceId != null) {
      final originalInvoiceIndex = invoices.indexWhere((inv) => inv.id == editingInvoiceId);
      if (originalInvoiceIndex >= 0) {
        final originalInvoice = invoices[originalInvoiceIndex];
        final originalLineIndex = originalInvoice.items.indexWhere((line) => line.item.id == lineItem.item.id);
        if (originalLineIndex >= 0) {
          originalQty = originalInvoice.items[originalLineIndex].quantity;
        }
      }
    }

    final newQty = await showDialog<int>(
      context: context,
      builder: (context) => ItemLineEditorDialog(
        item: lineItem.item,
        initialQuantity: lineItem.quantity,
        originalQuantity: originalQty,
      ),
    );

    if (newQty != null && mounted) {
      context.read<SalesInvoiceBloc>().add(AddOrUpdateLineItem(
            item: lineItem.item,
            quantity: newQty,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
          buildWhen: (previous, current) => previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            return Text(state.isEditingNew ? 'New Sales Invoice' : 'Edit Sales Invoice');
          },
        ),
      ),
      body: BlocConsumer<SalesInvoiceBloc, SalesInvoiceState>(
        listenWhen: (previous, current) => previous.successMessage != current.successMessage || previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.successMessage == 'Invoice saved successfully') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.successEmerald,
                content: Text(state.successMessage!),
              ),
            );
            context.read<SalesInvoiceBloc>().add(ClearMessages());
            Navigator.pop(context); // Close the editor page on success
          } else if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.errorRose,
                content: Text(state.errorMessage!),
              ),
            );
            context.read<SalesInvoiceBloc>().add(ClearMessages());
          }
        },
        builder: (context, state) {
          // Summary Totals
          double subtotal = 0.0;
          double gst = 0.0;
          for (final line in state.editingItems) {
            subtotal += line.subTotal;
            gst += line.taxAmount;
          }
          final total = subtotal + gst;

          final customer = state.editingCustomer;
          final date = state.editingDate ?? DateTime.now();

          return Column(
            children: [
              if (state.isLoading)
                const LinearProgressIndicator(color: AppTheme.primaryIndigo),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView(
                      padding: const EdgeInsets.all(16.0),
                      children: [
                        // Customer Selector Card
                        Card(
                          child: InkWell(
                            onTap: state.isEditingNew ? () => _showCustomerSelector(context) : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                                    child: const Icon(Icons.person, color: AppTheme.primaryIndigo),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CUSTOMER',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          customer?.name ?? 'Select Customer',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        if (customer != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            customer.companyName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                            ),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                  if (state.isEditingNew)
                                    Icon(
                                      Icons.keyboard_arrow_right,
                                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Date Picker Card
                        Card(
                          child: InkWell(
                            onTap: () => _selectInvoiceDate(date),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.infoSky.withValues(alpha: 0.1),
                                    child: const Icon(Icons.calendar_today, color: AppTheme.infoSky),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'INVOICE DATE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _dateFormat.format(date),
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_right,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Line Items Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Line Items',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            TextButton.icon(
                              onPressed: customer == null ? null : () => _openItemSearch(state.editingItems),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Item'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primaryIndigo,
                              ),
                            ),
                          ],
                        ),

                        if (state.editingItems.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 40.0),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 40,
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    customer == null ? 'Select customer to add items' : 'No items added yet',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: state.editingItems.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final line = state.editingItems[index];

                              return Card(
                                child: InkWell(
                                  onTap: () => _editLineItem(
                                    line,
                                    state.isEditingNew,
                                    state.editingInvoiceId,
                                    state.invoices,
                                  ),
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
                                                line.item.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'SKU: ${line.item.sku} | Rate: ₹${line.rate.toStringAsFixed(2)} | GST: ${line.taxPercentage}%',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Qty: ${line.quantity}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '₹${line.total.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppTheme.primaryIndigo,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppTheme.errorRose, size: 20),
                                          onPressed: () {
                                            context.read<SalesInvoiceBloc>().add(RemoveLineItem(line.item));
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 20),

                        // Notes Field
                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Invoice Notes',
                            hintText: 'Add remarks or special terms...',
                            prefixIcon: Icon(Icons.notes, color: AppTheme.primaryIndigo),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Billing Calculation and Save Button Drawer
              Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal:',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                            Text('₹${subtotal.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'GST (Tax):',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                            Text('₹${gst.toStringAsFixed(2)}'),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount:',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            Text(
                              '₹${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppTheme.primaryIndigo,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (customer == null || state.editingItems.isEmpty || state.isLoading)
                                ? null
                                : () {
                                    context.read<SalesInvoiceBloc>().add(SaveInvoice(
                                          notes: _notesController.text,
                                        ));
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryIndigo,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('SAVE SALES INVOICE'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
