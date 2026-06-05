import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../bloc/sales_return_bloc.dart';
import '../widgets/return_item_search_dialog.dart';
import '../widgets/return_invoice_selector_dialog.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../data/services/voucher_pdf_service.dart';

/// Screen for creating or editing a Sales Return (Credit Note).
class SalesReturnEditorPage extends StatefulWidget {
  const SalesReturnEditorPage({super.key});

  @override
  State<SalesReturnEditorPage> createState() => _SalesReturnEditorPageState();
}

class _SalesReturnEditorPageState extends State<SalesReturnEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  late TextEditingController _reasonController;
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  @override
  void initState() {
    super.initState();
    final blocState = context.read<SalesReturnBloc>().state;
    _reasonController = TextEditingController(text: blocState.editingReason);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectReturnDate(DateTime currentDate) async {
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
                    primary: AppTheme.warningAmber,
                    onPrimary: Colors.white,
                    surface: AppTheme.darkSurface,
                    onSurface: AppTheme.darkText,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.warningAmber,
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
      context.read<SalesReturnBloc>().add(UpdateReturnDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final cs = context.org.currencySymbol;
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
                          prefixIcon: const Icon(Icons.search, color: AppTheme.warningAmber),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                                          'Outstanding: $cs${customer.outstandingBalance.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              color: AppTheme.errorRose, fontSize: 11, fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                  onTap: () {
                                    this.context.read<SalesReturnBloc>().add(UpdateReturnCustomer(customer));
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

  Future<void> _openItemSearch(List<SalesReturnLineItem> editingItems) async {
    final customer = context.read<SalesReturnBloc>().state.editingCustomer;
    if (customer == null) return;

    final excludedIds = editingItems.map((line) => line.invoiceLineItem.item.id).toList();
    final result = await showDialog<List<SalesReturnLineItem>>(
      context: context,
      builder: (context) => ReturnItemSearchDialog(
        customerId: customer.id,
        excludedItemIds: excludedIds,
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final selectedItem = result.first.invoiceLineItem.item;
      context.read<SalesReturnBloc>().add(SetReturnLineItemsForProduct(
            item: selectedItem,
            lines: result,
          ));
    }
  }

  Future<void> _editLineItem(SalesReturnLineItem lineItem) async {
    final customer = context.read<SalesReturnBloc>().state.editingCustomer;
    if (customer == null) return;

    final editingItems = context.read<SalesReturnBloc>().state.editingItems;
    final itemLines = editingItems.where((line) => line.invoiceLineItem.item.id == lineItem.invoiceLineItem.item.id).toList();

    final result = await showDialog<List<SalesReturnLineItem>>(
      context: context,
      builder: (context) => ReturnInvoiceSelectorDialog(
        customer: customer,
        item: lineItem.invoiceLineItem.item,
        currentLines: itemLines,
      ),
    );

    if (result != null && mounted) {
      context.read<SalesReturnBloc>().add(SetReturnLineItemsForProduct(
            item: lineItem.invoiceLineItem.item,
            lines: result,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<SalesReturnBloc, SalesReturnState>(
          buildWhen: (previous, current) => previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            return Text(state.isEditingNew ? 'New Sales Return' : 'Edit Sales Return');
          },
        ),
      ),
      body: BlocConsumer<SalesReturnBloc, SalesReturnState>(
        listenWhen: (previous, current) =>
            previous.successMessage != current.successMessage || previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.successMessage == 'Return saved successfully') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.successEmerald,
                content: Text(state.successMessage!),
              ),
            );
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AppTheme.errorRose, content: Text(state.errorMessage!)),
            );
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
          }
        },
        builder: (context, state) {
          final cs = context.org.currencySymbol;
          final total = state.editingItems.fold(0.0, (sum, line) => sum + line.total);
          final customer = state.editingCustomer;
          final date = state.editingDate ?? DateTime.now();

          return Column(
            children: [
              if (state.isLoading) const LinearProgressIndicator(color: AppTheme.warningAmber),
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
                                    backgroundColor: AppTheme.warningAmber.withValues(alpha: 0.1),
                                    child: const Icon(Icons.person, color: AppTheme.warningAmber),
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
                                        ],
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
                            onTap: () => _selectReturnDate(date),
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
                                          'RETURN DATE',
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
                            const Text('Return Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            TextButton.icon(
                              onPressed: customer == null ? null : () => _openItemSearch(state.editingItems),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Item'),
                              style: TextButton.styleFrom(foregroundColor: AppTheme.warningAmber),
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
                                    Icons.assignment_return_outlined,
                                    size: 40,
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    customer == null ? 'Select customer to add return items' : 'No items added yet',
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
                              final item = line.invoiceLineItem.item;

                              return Card(
                                child: InkWell(
                                  onTap: () => _editLineItem(line),
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
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'SKU: ${item.sku} | Rate: $cs${line.invoiceLineItem.rate.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                                ),
                                              ),
                                              if (line.invoiceNumber != null) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Invoice: ${line.invoiceNumber}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.warningAmber,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Qty: ${line.returnedQuantity}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$cs${line.total.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppTheme.warningAmber,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppTheme.errorRose, size: 20),
                                          onPressed: () {
                                            context.read<SalesReturnBloc>().add(RemoveReturnLineItem(item));
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

                        // Reason Field
                        TextFormField(
                          controller: _reasonController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Reason for Return',
                            hintText: 'Damaged goods, wrong item, surplus...',
                            prefixIcon: Icon(Icons.notes, color: AppTheme.warningAmber),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Total and Save Button
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
                            const Text(
                              'Return Total:',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            Text(
                              '$cs${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppTheme.warningAmber,
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
                                    context.read<SalesReturnBloc>().add(SaveReturn(
                                          reason: _reasonController.text,
                                        ));
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.warningAmber,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('SAVE SALES RETURN'),
                          ),
                        ),
                        if (!state.isEditingNew) ...[
                          const SizedBox(height: 16),
                          VoucherPdfActionsWidget(
                            type: VoucherType.salesReturn,
                            voucher: SalesReturn(
                              id: state.editingReturnId ?? '',
                              creditNoteNumber: state.returns
                                  .firstWhere(
                                    (r) => r.id == state.editingReturnId,
                                    orElse: () => SalesReturn(
                                      id: '',
                                      creditNoteNumber: 'RTN-TEMP',
                                      customerId: '',
                                      customerName: '',
                                      date: DateTime.now(),
                                      items: const [],
                                      reason: '',
                                    ),
                                  )
                                  .creditNoteNumber,
                              customerId: customer?.id ?? '',
                              customerName: customer?.name ?? '',
                              date: date,
                              items: state.editingItems,
                              reason: _reasonController.text,
                            ),
                          ),
                        ],
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
