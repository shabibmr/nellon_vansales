import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/customer_selector_sheet.dart';
import '../../../../ui/core/widgets/editor_footer.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../../../../ui/core/widgets/line_item_list.dart';
import '../bloc/sales_return_bloc.dart';
import '../widgets/return_item_search_dialog.dart';
import '../widgets/return_invoice_selector_dialog.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../data/services/voucher_pdf_service.dart';

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
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
      color: AppTheme.warningAmber,
    );
    if (picked != null && mounted) {
      context.read<SalesReturnBloc>().add(UpdateReturnDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final allCustomers = _db.getCustomers()..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      accentColor: AppTheme.warningAmber,
      onSelected: (customer) {
        context.read<SalesReturnBloc>().add(UpdateReturnCustomer(customer));
      },
    );
  }

  Future<void> _openItemSearch(List<SalesReturnLineItem> editingItems) async {
    final customer = context.read<SalesReturnBloc>().state.editingCustomer;
    if (customer == null) return;

    final excludedIds = editingItems.map((line) => line.invoiceLineItem.item.id).toList();
    final result = await ReturnItemSearchDialog.show(
      context,
      customerId: customer.id,
      excludedItemIds: excludedIds,
    );

    if (result != null && result.isNotEmpty && mounted) {
      final selectedItem = result.first.invoiceLineItem.item;
      context.read<SalesReturnBloc>().add(SetReturnLineItemsForProduct(item: selectedItem, lines: result));
    }
  }

  Future<void> _editLineItem(SalesReturnLineItem lineItem) async {
    final customer = context.read<SalesReturnBloc>().state.editingCustomer;
    if (customer == null) return;

    final editingItems = context.read<SalesReturnBloc>().state.editingItems;
    final itemLines = editingItems
        .where((line) => line.invoiceLineItem.item.id == lineItem.invoiceLineItem.item.id)
        .toList();

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
          builder: (context, state) => Text(state.isEditingNew ? 'New Sales Return' : 'Edit Sales Return'),
        ),
      ),
      body: BlocConsumer<SalesReturnBloc, SalesReturnState>(
        listenWhen: (previous, current) =>
            previous.successMessage != current.successMessage || previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.successMessage == 'Return saved successfully') {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<SalesReturnBloc>().add(ClearReturnMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
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
                          EmptyStateCard(
                            icon: Icons.assignment_return_outlined,
                            message: customer == null ? 'Select customer to add return items' : 'No items added yet',
                          )
                        else
                          LineItemList(
                            items: state.editingItems
                                .map((line) => LineItemRow(
                                      name: line.invoiceLineItem.item.name,
                                      sku: line.invoiceLineItem.item.sku,
                                      rate: line.invoiceLineItem.rate,
                                      taxPercentage: 0,
                                      quantity: line.returnedQuantity,
                                      total: line.total,
                                      accentColor: AppTheme.warningAmber,
                                    ))
                                .toList(),
                            currencySymbol: cs,
                            onEdit: (index) => _editLineItem(state.editingItems[index]),
                            onRemove: (index) {
                              context.read<SalesReturnBloc>().add(
                                    RemoveReturnLineItem(state.editingItems[index].invoiceLineItem.item),
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

              EditorFooter(
                rows: [
                  (label: 'Return Total:', value: formatCurrency(total, cs), emphasize: true),
                ],
                buttonLabel: 'SAVE SALES RETURN',
                buttonColor: AppTheme.warningAmber,
                accentColor: AppTheme.warningAmber,
                onSave: (customer == null || state.editingItems.isEmpty || state.isLoading)
                    ? null
                    : () {
                        context.read<SalesReturnBloc>().add(SaveReturn(reason: _reasonController.text));
                      },
                trailing: !state.isEditingNew
                    ? VoucherPdfActionsWidget(
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
                      )
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
