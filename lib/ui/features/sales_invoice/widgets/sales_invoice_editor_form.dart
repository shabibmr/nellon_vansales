import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/customer_selector_sheet.dart';
import '../../../core/widgets/editor_footer.dart';
import '../../../core/widgets/item_line_editor_dialog.dart';
import '../../../core/widgets/item_search_sheet.dart';
import '../../dashboard/widgets/create_customer_dialog.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../bloc/sales_invoice_editor_bloc.dart';
import '../bloc/sales_invoice_editor_event.dart';
import '../bloc/sales_invoice_editor_state.dart';
import 'sales_invoice_customer_card.dart';
import 'sales_invoice_date_card.dart';
import 'sales_invoice_line_items_section.dart';
import 'sales_invoice_notes_field.dart';

/// Main form body for the sales invoice editor (scroll area + footer).
class SalesInvoiceEditorForm extends StatelessWidget {
  final SalesInvoiceEditorState state;
  final bool readOnly;
  final TextEditingController notesController;

  const SalesInvoiceEditorForm({
    super.key,
    required this.state,
    required this.readOnly,
    required this.notesController,
  });

  Future<void> _selectInvoiceDate(
    BuildContext context,
    DateTime currentDate,
  ) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
    );
    if (picked != null && context.mounted) {
      context.read<SalesInvoiceEditorBloc>().add(UpdateInvoiceDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final db = sl<HiveDatabaseService>();
    final allCustomers = db.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        context.read<SalesInvoiceEditorBloc>().add(UpdateInvoiceCustomer(customer));
      },
      showCreateOption: true,
      createOptionSubtitle: 'Add a new customer and use it for this invoice',
      onCreateTap: () async {
        final bloc = context.read<SalesInvoiceEditorBloc>();
        final created = await CreateCustomerDialog.show(context);
        if (created != null) {
          bloc.add(UpdateInvoiceCustomer(created));
        }
      },
    );
  }

  Future<void> _openItemSearch(
    BuildContext context,
    List<InvoiceLineItem> editingItems,
  ) async {
    final db = sl<HiveDatabaseService>();
    final excludedIds = editingItems.map((line) => line.item.id).toList();
    final items = db
        .getItems()
        .where((item) => !excludedIds.contains(item.id))
        .toList();

    ItemLineEditorResult? result;
    Item? pickedItem;
    await ItemSearchSheet.show<void>(
      context,
      items: items,
      title: 'Search Van Inventory',
      emptyMessage: 'No items available in van stock',
      onSelected: (item, sheetContext) async {
        final editorResult = await showDialog<ItemLineEditorResult>(
          context: sheetContext,
          builder: (context) => SharedItemLineEditorDialog(
            item: item,
            title: 'Invoice Line Item Details',
          ),
        );
        if (editorResult != null && editorResult.quantity > 0) {
          result = editorResult;
          pickedItem = item;
          if (sheetContext.mounted) Navigator.pop(sheetContext, null);
        }
      },
    );

    if (result != null && pickedItem != null && context.mounted) {
      context.read<SalesInvoiceEditorBloc>().add(
        AddOrUpdateLineItem(
          item: pickedItem!,
          quantity: result!.quantity,
          rate: result!.rate,
          discount: result!.discount,
          uom: result!.uom,
          unitConversionId: result!.unitConversionId,
        ),
      );
    }
  }

  Future<Item> _resolveUnits(BuildContext context, Item item) async {
    if (item.unitConversions.isNotEmpty) return item;
    final result = await sl<SalesRepository>().resolveItemUnitConversions(item);
    if (result.offlineFallback && context.mounted) {
      showErrorSnackBar(
        context,
        "Couldn't load other units — using base unit.",
      );
    }
    return result.item;
  }

  Future<void> _editLineItem(
    BuildContext context,
    InvoiceLineItem lineItem,
    bool isEditingNew,
    SalesInvoice? editingInvoice,
  ) async {
    double originalBaseQty = 0;
    if (!isEditingNew && editingInvoice != null) {
      final originalLineIndex = editingInvoice.items.indexWhere(
        (line) => line.item.id == lineItem.item.id,
      );
      if (originalLineIndex >= 0) {
        originalBaseQty = editingInvoice.items[originalLineIndex].quantityInBase;
      }
    }

    final resolved = await _resolveUnits(context, lineItem.item);
    if (!context.mounted) return;

    final result = await showDialog<ItemLineEditorResult>(
      context: context,
      builder: (context) => SharedItemLineEditorDialog(
        item: resolved,
        initialQuantity: lineItem.quantity,
        originalQuantity: originalBaseQty,
        title: 'Invoice Line Item Details',
        initialRate: lineItem.rate,
        initialDiscount: lineItem.discount,
        initialUom: lineItem.displayUom,
      ),
    );

    if (result != null && context.mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final customer = state.editingCustomer;
    final date = state.editingDate ?? DateTime.now();
    final tempInvoice = SalesInvoice(
      id: '',
      invoiceNumber: '',
      customerId: customer?.id ?? '',
      customerName: customer?.name ?? '',
      date: date,
      dueDate: date.add(const Duration(days: 7)),
      items: state.editingItems,
      notes: '',
    );

    final showTrailingPdf = !state.isEditingNew &&
        state.editingInvoiceId != null &&
        customer != null;

    return Column(
      children: [
        if (state.isSaving)
          const LinearProgressIndicator(color: AppTheme.primaryIndigo),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  SalesInvoiceCustomerCard(
                    customer: customer,
                    canSelect: !readOnly && state.isEditingNew,
                    onTap: () => _showCustomerSelector(context),
                  ),
                  const SizedBox(height: 12),
                  SalesInvoiceDateCard(
                    label: 'INVOICE DATE',
                    date: date,
                    icon: Icons.calendar_today,
                    accentColor: AppTheme.primaryIndigo,
                    onTap: readOnly ? null : () => _selectInvoiceDate(context, date),
                  ),
                  const SizedBox(height: 20),
                  SalesInvoiceLineItemsSection(
                    items: state.editingItems,
                    currencySymbol: cs,
                    readOnly: readOnly,
                    onAdd: () => _openItemSearch(context, state.editingItems),
                    onEdit: (index) => _editLineItem(
                      context,
                      state.editingItems[index],
                      state.isEditingNew,
                      state.editingInvoice,
                    ),
                    onRemove: (index) {
                      context.read<SalesInvoiceEditorBloc>().add(
                        RemoveLineItem(state.editingItems[index].item),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  SalesInvoiceNotesField(
                    controller: notesController,
                    readOnly: readOnly,
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
              value: formatCurrency(tempInvoice.subTotal, cs),
              emphasize: false,
            ),
            if (tempInvoice.discountTotal > 0)
              (
                label: 'Discount Total:',
                value: formatCurrency(tempInvoice.discountTotal, cs),
                emphasize: false,
              ),
            (
              label: 'VAT (Tax):',
              value: formatCurrency(tempInvoice.taxTotal, cs),
              emphasize: false,
            ),
            if (tempInvoice.roundOff != 0)
              (
                label: 'Round Off:',
                value: formatCurrency(tempInvoice.roundOff, cs),
                emphasize: false,
              ),
            (
              label: 'Total Amount:',
              value: formatCurrency(tempInvoice.total, cs),
              emphasize: true,
            ),
          ],
          buttonLabel: readOnly ? 'CLOSE' : 'SAVE INVOICE',
          buttonColor: AppTheme.primaryIndigo,
          onSave: readOnly
              ? () => Navigator.pop(context)
              : (customer == null ||
                    state.editingItems.isEmpty ||
                    state.isSaving)
              ? null
              : () {
                  context.read<SalesInvoiceEditorBloc>().add(
                    SaveInvoice(notes: notesController.text),
                  );
                },
          trailing: showTrailingPdf && state.editingInvoice != null
              ? VoucherPdfActionsWidget(
                  type: VoucherType.salesInvoice,
                  voucher: state.editingInvoice!,
                )
              : null,
        ),
      ],
    );
  }
}
