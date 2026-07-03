import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/sales_invoice.dart';
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
import '../bloc/sales_invoice_bloc.dart';
import '../widgets/item_line_editor_dialog.dart';
import '../widgets/item_search_dialog.dart';
import '../../dashboard/widgets/create_customer_dialog.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../data/services/voucher_pdf_service.dart';

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
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
    );
    if (picked != null && mounted) {
      context.read<SalesInvoiceBloc>().add(UpdateInvoiceDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final allCustomers = _db.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        context.read<SalesInvoiceBloc>().add(UpdateInvoiceCustomer(customer));
      },
      showCreateOption: true,
      createOptionSubtitle: 'Add a new customer and use it for this invoice',
      onCreateTap: () async {
        final created = await CreateCustomerDialog.show(context);
        if (created != null && mounted) {
          context.read<SalesInvoiceBloc>().add(UpdateInvoiceCustomer(created));
        }
      },
    );
  }

  Future<void> _openItemSearch(List<InvoiceLineItem> editingItems) async {
    final excludedIds = editingItems.map((line) => line.item.id).toList();
    final result = await ItemSearchDialog.show(
      context,
      excludedItemIds: excludedIds,
    );
    if (result != null && mounted) {
      final (item, qty, rate, discount) = result;
      context.read<SalesInvoiceBloc>().add(
        AddOrUpdateLineItem(
          item: item,
          quantity: qty,
          rate: rate,
          discount: discount,
        ),
      );
    }
  }

  Future<void> _editLineItem(
    InvoiceLineItem lineItem,
    bool isEditingNew,
    String? editingInvoiceId,
    List<SalesInvoice> invoices,
  ) async {
    int originalQty = 0;
    if (!isEditingNew && editingInvoiceId != null) {
      final originalInvoiceIndex = invoices.indexWhere(
        (inv) => inv.id == editingInvoiceId,
      );
      if (originalInvoiceIndex >= 0) {
        final originalInvoice = invoices[originalInvoiceIndex];
        final originalLineIndex = originalInvoice.items.indexWhere(
          (line) => line.item.id == lineItem.item.id,
        );
        if (originalLineIndex >= 0) {
          originalQty = originalInvoice.items[originalLineIndex].quantity;
        }
      }
    }

    final result = await showDialog<(int, double, double)>(
      context: context,
      builder: (context) => ItemLineEditorDialog(
        item: lineItem.item,
        initialQuantity: lineItem.quantity,
        originalQuantity: originalQty,
        initialRate: lineItem.rate,
        initialDiscount: lineItem.discount,
      ),
    );

    if (result != null && mounted) {
      final (newQty, newRate, newDiscount) = result;
      context.read<SalesInvoiceBloc>().add(
        AddOrUpdateLineItem(
          item: lineItem.item,
          quantity: newQty,
          rate: newRate,
          discount: newDiscount,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) => Text(
            state.isEditingNew ? 'New Sales Invoice' : 'Edit Sales Invoice',
          ),
        ),
      ),
      body: BlocConsumer<SalesInvoiceBloc, SalesInvoiceState>(
        listenWhen: (previous, current) =>
            previous.successMessage != current.successMessage ||
            previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.successMessage == 'Invoice saved successfully') {
            showSuccessSnackBar(context, state.successMessage!);
            context.read<SalesInvoiceBloc>().add(ClearMessages());
            Navigator.pop(context);
          } else if (state.errorMessage != null) {
            showErrorSnackBar(context, state.errorMessage!);
            context.read<SalesInvoiceBloc>().add(ClearMessages());
          }
        },
        builder: (context, state) {
          final cs = context.org.currencySymbol;
          final tempInvoice = SalesInvoice(
            id: '',
            invoiceNumber: '',
            customerId: state.editingCustomer?.id ?? '',
            customerName: state.editingCustomer?.name ?? '',
            date: state.editingDate ?? DateTime.now(),
            dueDate: state.editingDate ?? DateTime.now(),
            items: state.editingItems,
            notes: '',
          );
          final subtotal = tempInvoice.subTotal;
          final vat = tempInvoice.taxTotal;
          final discountTotal = tempInvoice.discountTotal;
          final roundOff = tempInvoice.roundOff;
          final total = tempInvoice.total;
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
                            onTap: state.isEditingNew
                                ? () => _showCustomerSelector(context)
                                : null,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primaryIndigo
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.person,
                                      color: AppTheme.primaryIndigo,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CUSTOMER',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          customer?.name ?? 'Select Customer',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (customer != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            customer.companyName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? AppTheme.darkTextSecondary
                                                  : AppTheme.lightTextSecondary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (state.isEditingNew)
                                    Icon(
                                      Icons.keyboard_arrow_right,
                                      color: isDark
                                          ? AppTheme.darkTextSecondary
                                          : AppTheme.lightTextSecondary,
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
                                    backgroundColor: AppTheme.infoSky
                                        .withValues(alpha: 0.1),
                                    child: const Icon(
                                      Icons.calendar_today,
                                      color: AppTheme.infoSky,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'INVOICE DATE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.lightTextSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _dateFormat.format(date),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_right,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
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
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: customer == null
                                  ? null
                                  : () => _openItemSearch(state.editingItems),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Item'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primaryIndigo,
                              ),
                            ),
                          ],
                        ),

                        if (state.editingItems.isEmpty)
                          EmptyStateCard(
                            icon: Icons.shopping_cart_outlined,
                            message: customer == null
                                ? 'Select customer to add items'
                                : 'No items added yet',
                          )
                        else
                          LineItemList(
                            items: state.editingItems
                                .map(
                                  (line) => LineItemRow(
                                    name: line.item.name,
                                    sku: line.item.sku,
                                    rate: line.rate,
                                    taxPercentage: line.taxPercentage,
                                    quantity: line.quantity,
                                    total: line.total,
                                    discount: line.discount,
                                  ),
                                )
                                .toList(),
                            currencySymbol: cs,
                            onEdit: (index) => _editLineItem(
                              state.editingItems[index],
                              state.isEditingNew,
                              state.editingInvoiceId,
                              state.invoices,
                            ),
                            onRemove: (index) {
                              context.read<SalesInvoiceBloc>().add(
                                RemoveLineItem(state.editingItems[index].item),
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
                            prefixIcon: Icon(
                              Icons.notes,
                              color: AppTheme.primaryIndigo,
                            ),
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
                  (
                    label: 'Subtotal:',
                    value: formatCurrency(subtotal, cs),
                    emphasize: false,
                  ),
                  if (discountTotal > 0)
                    (
                      label: 'Discount Total:',
                      value: formatCurrency(discountTotal, cs),
                      emphasize: false,
                    ),
                  (
                    label: 'VAT (Tax):',
                    value: formatCurrency(vat, cs),
                    emphasize: false,
                  ),
                  if (roundOff != 0)
                    (
                      label: 'Round Off:',
                      value: formatCurrency(roundOff, cs),
                      emphasize: false,
                    ),
                  (
                    label: 'Total Amount:',
                    value: formatCurrency(total, cs),
                    emphasize: true,
                  ),
                ],
                buttonLabel: 'SAVE SALES INVOICE',
                buttonColor: AppTheme.primaryIndigo,
                onSave:
                    (customer == null ||
                        state.editingItems.isEmpty ||
                        state.isLoading)
                    ? null
                    : () {
                        context.read<SalesInvoiceBloc>().add(
                          SaveInvoice(notes: _notesController.text),
                        );
                      },
                trailing: !state.isEditingNew
                    ? VoucherPdfActionsWidget(
                        type: VoucherType.salesInvoice,
                        voucher: SalesInvoice(
                          id: state.editingInvoiceId ?? '',
                          invoiceNumber: state.invoices
                              .firstWhere(
                                (inv) => inv.id == state.editingInvoiceId,
                                orElse: () => SalesInvoice(
                                  id: '',
                                  invoiceNumber: 'INV-TEMP',
                                  customerId: '',
                                  customerName: '',
                                  date: DateTime.now(),
                                  dueDate: DateTime.now(),
                                  items: const [],
                                  notes: '',
                                ),
                              )
                              .invoiceNumber,
                          customerId: customer?.id ?? '',
                          customerName: customer?.name ?? '',
                          date: date,
                          dueDate:
                              state.editingDate?.add(
                                const Duration(days: 30),
                              ) ??
                              DateTime.now(),
                          items: state.editingItems,
                          notes: _notesController.text,
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
