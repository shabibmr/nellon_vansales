import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/customer_selector_sheet.dart';
import '../../../../ui/core/widgets/item_line_editor_dialog.dart';
import '../../../../ui/core/widgets/item_search_sheet.dart';
import '../../dashboard/widgets/create_customer_dialog.dart';
import '../bloc/sales_order_editor_bloc.dart';
import '../bloc/sales_order_editor_event.dart';
import '../bloc/sales_order_editor_state.dart';
import 'sales_order_customer_card.dart';
import 'sales_order_date_card.dart';
import 'sales_order_editor_footer_sheet.dart';
import 'sales_order_line_items_section.dart';
import 'sales_order_notes_field.dart';

/// Main form body for the sales order editor (scroll area + footer).
///
/// Owns item-search / line-edit interactions so the page stays a thin shell.
class SalesOrderEditorForm extends StatelessWidget {
  final SalesOrderEditorState state;
  final bool readOnly;
  final TextEditingController notesController;

  const SalesOrderEditorForm({
    super.key,
    required this.state,
    required this.readOnly,
    required this.notesController,
  });

  Future<void> _selectShipmentDate(
    BuildContext context,
    DateTime currentDate,
  ) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
    );
    if (picked != null && context.mounted) {
      context.read<SalesOrderEditorBloc>().add(UpdateOrderShipmentDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final repo = context.read<SalesRepository>();
    final allCustomers = repo.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        context.read<SalesOrderEditorBloc>().add(UpdateOrderCustomer(customer));
      },
      showCreateOption: true,
      createOptionSubtitle: 'Add a new customer and use it for this order',
      onCreateTap: () async {
        final bloc = context.read<SalesOrderEditorBloc>();
        final created = await CreateCustomerDialog.show(context);
        if (created != null) {
          bloc.add(UpdateOrderCustomer(created));
        }
      },
    );
  }

  Future<void> _openItemSearch(
    BuildContext context,
    List<OrderLineItem> editingItems,
  ) async {
    final repo = context.read<SalesRepository>();
    final excludedIds = editingItems.map((line) => line.item.id).toList();
    final items = repo
        .getItems()
        .where((item) => !excludedIds.contains(item.id))
        .toList();

    ItemLineEditorResult? result;
    Item? pickedItem;
    await ItemSearchSheet.show<void>(
      context,
      items: items,
      title: 'Search Items',
      emptyMessage: 'No items available to add',
      onSelected: (item, sheetContext) async {
        final editorResult = await showDialog<ItemLineEditorResult>(
          context: sheetContext,
          builder: (context) => SharedItemLineEditorDialog(
            item: item,
            allowUnlimitedQuantity: true,
            title: 'Order Line Item Details',
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
      context.read<SalesOrderEditorBloc>().add(
        AddOrUpdateOrderLine(
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
    final result =
        await context.read<SalesRepository>().resolveItemUnitConversions(item);
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
    OrderLineItem lineItem,
    bool isEditingNew,
    SalesOrder? editingOrder,
  ) async {
    double originalBaseQty = 0;
    if (!isEditingNew && editingOrder != null) {
      final originalLineIndex = editingOrder.items.indexWhere(
        (line) => line.item.id == lineItem.item.id,
      );
      if (originalLineIndex >= 0) {
        originalBaseQty = editingOrder.items[originalLineIndex].quantityInBase;
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
        allowUnlimitedQuantity: true,
        title: 'Order Line Item Details',
        initialRate: lineItem.rate,
        initialDiscount: lineItem.discount,
        initialUom: lineItem.displayUom,
      ),
    );

    if (result != null && context.mounted) {
      context.read<SalesOrderEditorBloc>().add(
        AddOrUpdateOrderLine(
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
    final shipmentDate = state.editingShipmentDate ?? date;
    final tempOrder = SalesOrder(
      id: '',
      orderNumber: '',
      customerId: customer?.id ?? '',
      customerName: customer?.name ?? '',
      date: date,
      shipmentDate: shipmentDate,
      items: state.editingItems,
      notes: '',
    );

    final footerRows = <({String label, String value, bool emphasize})>[
      (
        label: 'Subtotal:',
        value: formatCurrency(tempOrder.subTotal, cs),
        emphasize: false,
      ),
      if (tempOrder.discountTotal > 0)
        (
          label: 'Discount Total:',
          value: formatCurrency(tempOrder.discountTotal, cs),
          emphasize: false,
        ),
      (
        label: 'VAT (Tax):',
        value: formatCurrency(tempOrder.taxTotal, cs),
        emphasize: false,
      ),
      if (tempOrder.roundOff != 0)
        (
          label: 'Round Off:',
          value: formatCurrency(tempOrder.roundOff, cs),
          emphasize: false,
        ),
      (
        label: 'Total Amount:',
        value: formatCurrency(tempOrder.total, cs),
        emphasize: true,
      ),
    ];

    final showDocumentActions = !state.isEditingNew;
    // Leave room under the list for the collapsed sheet (total + save).
    final listBottomPad = showDocumentActions ? 150.0 : 130.0;

    return Column(
      children: [
        if (state.isSaving)
          const LinearProgressIndicator(color: AppTheme.primaryIndigo),
        Expanded(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPad),
                    children: [
                      SalesOrderCustomerCard(
                        customer: customer,
                        canSelect: !readOnly && state.isEditingNew,
                        onTap: () => _showCustomerSelector(context),
                      ),
                      const SizedBox(height: 12),
                      SalesOrderDateCard(
                        label: 'ORDER DATE',
                        date: date,
                        icon: Icons.calendar_today,
                        accentColor: AppTheme.infoSky,
                      ),
                      const SizedBox(height: 12),
                      SalesOrderDateCard(
                        label: 'EXPECTED SHIPPING DATE',
                        date: shipmentDate,
                        icon: Icons.local_shipping_outlined,
                        accentColor: AppTheme.warningAmber,
                        onTap: readOnly
                            ? null
                            : () =>
                                _selectShipmentDate(context, shipmentDate),
                      ),
                      const SizedBox(height: 20),
                      SalesOrderLineItemsSection(
                        items: state.editingItems,
                        currencySymbol: cs,
                        readOnly: readOnly,
                        hasCustomer: customer != null,
                        onAdd: () =>
                            _openItemSearch(context, state.editingItems),
                        onEdit: (index) => _editLineItem(
                          context,
                          state.editingItems[index],
                          state.isEditingNew,
                          state.editingOrder,
                        ),
                        onRemove: (index) {
                          context.read<SalesOrderEditorBloc>().add(
                            RemoveOrderLine(state.editingItems[index].item),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      SalesOrderNotesField(
                        controller: notesController,
                        readOnly: readOnly,
                        onChanged: readOnly
                            ? null
                            : (value) => context
                                .read<SalesOrderEditorBloc>()
                                .add(UpdateOrderNotes(value)),
                      ),
                    ],
                  ),
                ),
              ),
              SalesOrderEditorFooterSheet(
                rows: footerRows,
                buttonLabel: readOnly ? 'CLOSE' : 'SAVE',
                showDocumentActions: showDocumentActions,
                state: state,
                customer: customer,
                orderDate: date,
                notes: notesController.text,
                onSave: readOnly
                    ? () => Navigator.pop(context)
                    : (customer == null ||
                            state.editingItems.isEmpty ||
                            state.isSaving)
                        ? null
                        : () {
                            context.read<SalesOrderEditorBloc>().add(
                              SaveSalesOrder(notes: notesController.text),
                            );
                          },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
