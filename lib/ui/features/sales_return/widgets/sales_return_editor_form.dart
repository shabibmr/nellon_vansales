import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/widgets/customer_selector_sheet.dart';
import '../../../core/widgets/editor_footer.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../bloc/sales_return_editor_bloc.dart';
import '../bloc/sales_return_editor_event.dart';
import '../bloc/sales_return_editor_state.dart';
import 'return_invoice_selector_dialog.dart';
import 'return_item_search_dialog.dart';
import 'sales_return_customer_card.dart';
import 'sales_return_date_card.dart';
import 'sales_return_line_items_section.dart';
import 'sales_return_notes_field.dart';

/// Main form body for the sales return editor (scroll area + footer).
class SalesReturnEditorForm extends StatelessWidget {
  final SalesReturnEditorState state;
  final bool readOnly;
  final TextEditingController reasonController;

  const SalesReturnEditorForm({
    super.key,
    required this.state,
    required this.readOnly,
    required this.reasonController,
  });

  Future<void> _selectReturnDate(
    BuildContext context,
    DateTime currentDate,
  ) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
      color: AppTheme.warningAmber,
    );
    if (picked != null && context.mounted) {
      context.read<SalesReturnEditorBloc>().add(UpdateReturnDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final db = sl<HiveDatabaseService>();
    final allCustomers = db.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      accentColor: AppTheme.warningAmber,
      onSelected: (customer) {
        context.read<SalesReturnEditorBloc>().add(UpdateReturnCustomer(customer));
      },
    );
  }

  Future<void> _openItemSearch(
    BuildContext context,
    List<SalesReturnLineItem> editingItems,
  ) async {
    final customer = state.editingCustomer;
    if (customer == null) return;

    final excludedIds = editingItems
        .map((line) => line.invoiceLineItem.item.id)
        .toList();
    final result = await ReturnItemSearchDialog.show(
      context,
      customerId: customer.id,
      excludedItemIds: excludedIds,
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      final selectedItem = result.first.invoiceLineItem.item;
      context.read<SalesReturnEditorBloc>().add(
        SetReturnLineItemsForProduct(item: selectedItem, lines: result),
      );
    }
  }

  Future<void> _editLineItem(
    BuildContext context,
    SalesReturnLineItem lineItem,
  ) async {
    final customer = state.editingCustomer;
    if (customer == null) return;

    final editingItems = state.editingItems;
    final itemLines = editingItems
        .where(
          (line) =>
              line.invoiceLineItem.item.id == lineItem.invoiceLineItem.item.id,
        )
        .toList();

    final result = await showDialog<List<SalesReturnLineItem>>(
      context: context,
      builder: (context) => ReturnInvoiceSelectorDialog(
        customer: customer,
        item: lineItem.invoiceLineItem.item,
        currentLines: itemLines,
      ),
    );

    if (result != null && context.mounted) {
      context.read<SalesReturnEditorBloc>().add(
        SetReturnLineItemsForProduct(
          item: lineItem.invoiceLineItem.item,
          lines: result,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    final customer = state.editingCustomer;
    final date = state.editingDate ?? DateTime.now();

    final totalAmount = state.editingItems.fold(
      0.0,
      (sum, line) => sum + line.total,
    );

    final showTrailingPdf = !state.isEditingNew &&
        state.editingReturnId != null &&
        customer != null;

    return Column(
      children: [
        if (state.isSaving)
          const LinearProgressIndicator(color: AppTheme.warningAmber),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  SalesReturnCustomerCard(
                    customer: customer,
                    canSelect: !readOnly && state.isEditingNew,
                    onTap: () => _showCustomerSelector(context),
                  ),
                  const SizedBox(height: 12),
                  SalesReturnDateCard(
                    label: 'RETURN DATE',
                    date: date,
                    icon: Icons.calendar_today,
                    accentColor: AppTheme.warningAmber,
                    onTap: readOnly
                        ? null
                        : () => _selectReturnDate(context, date),
                  ),
                  const SizedBox(height: 20),
                  SalesReturnLineItemsSection(
                    items: state.editingItems,
                    currencySymbol: cs,
                    readOnly: readOnly,
                    hasCustomer: customer != null,
                    onAdd: () => _openItemSearch(context, state.editingItems),
                    onEdit: (index) => _editLineItem(
                      context,
                      state.editingItems[index],
                    ),
                    onRemove: (index) {
                      context.read<SalesReturnEditorBloc>().add(
                        RemoveReturnLineItem(
                          state.editingItems[index].invoiceLineItem.item,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  SalesReturnNotesField(
                    controller: reasonController,
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
              label: 'Total Return Value:',
              value: formatCurrency(totalAmount, cs),
              emphasize: true,
            ),
          ],
          buttonLabel: readOnly ? 'CLOSE' : 'SAVE SALES RETURN',
          buttonColor: AppTheme.warningAmber,
          onSave: readOnly
              ? () => Navigator.pop(context)
              : (customer == null ||
                    state.editingItems.isEmpty ||
                    state.isSaving)
              ? null
              : () {
                  context.read<SalesReturnEditorBloc>().add(
                    SaveReturn(reason: reasonController.text),
                  );
                },
          trailing: showTrailingPdf && state.editingReturn != null
              ? VoucherPdfActionsWidget(
                  type: VoucherType.salesReturn,
                  voucher: state.editingReturn!,
                )
              : null,
        ),
      ],
    );
  }
}
