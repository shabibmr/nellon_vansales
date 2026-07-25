import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../../domain/models/item.dart';
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
import '../../../../ui/core/widgets/item_line_editor_dialog.dart';
import '../../../../ui/core/widgets/item_search_sheet.dart';
import '../../../../ui/core/widgets/line_item_list.dart';
import '../bloc/sales_order_bloc.dart';
import '../../voucher_pdf/widgets/voucher_pdf_actions_widget.dart';
import '../../../../domain/repositories/voucher_pdf_repository.dart';
import '../../dashboard/widgets/create_customer_dialog.dart';
import '../../sales_invoice/bloc/sales_invoice_bloc.dart'
    show SalesInvoiceBloc, StartInvoiceFromOrder;
import '../../sales_invoice/views/sales_invoice_editor_page.dart';

class SalesOrderEditorPage extends StatefulWidget {
  /// When true, opens in view mode. The user can switch to edit via the
  /// app-bar Edit action (sales orders are the only editable vouchers).
  final bool readOnly;

  const SalesOrderEditorPage({super.key, this.readOnly = false});

  @override
  State<SalesOrderEditorPage> createState() => _SalesOrderEditorPageState();
}

class _SalesOrderEditorPageState extends State<SalesOrderEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  late TextEditingController _notesController;
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  /// Local view-mode flag so the Edit button can unlock the form without
  /// rebuilding the route.
  late bool _isViewMode;

  @override
  void initState() {
    super.initState();
    _isViewMode = widget.readOnly;
    final blocState = context.read<SalesOrderBloc>().state;
    _notesController = TextEditingController(text: blocState.editingNotes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  /// Builds the "Convert to Invoice" action shown for saved orders, or a
  /// "Converted" indicator once the order has already been invoiced.
  Widget _buildConvertAction(BuildContext context, SalesOrder order) {
    if (order.isConverted) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Text(
            order.convertedInvoiceNumber != null
                ? 'Converted to ${order.convertedInvoiceNumber}'
                : 'Converted to invoice',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.receipt_long),
        label: const Text('CONVERT TO INVOICE'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryIndigo,
          side: const BorderSide(color: AppTheme.primaryIndigo),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () {
          context.read<SalesInvoiceBloc>().add(StartInvoiceFromOrder(order));
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SalesInvoiceEditorPage(),
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectShipmentDate(DateTime currentDate) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
    );
    if (picked != null && mounted) {
      context.read<SalesOrderBloc>().add(UpdateShipmentDate(picked));
    }
  }

  void _showCustomerSelector(BuildContext context) {
    final allCustomers = _db.getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        context.read<SalesOrderBloc>().add(UpdateOrderCustomer(customer));
      },
      showCreateOption: true,
      createOptionSubtitle: 'Add a new customer and use it for this order',
      onCreateTap: () async {
        final bloc = context.read<SalesOrderBloc>();
        final created = await CreateCustomerDialog.show(context);
        if (created != null) {
          bloc.add(UpdateOrderCustomer(created));
        }
      },
    );
  }

  Future<void> _openItemSearch(List<OrderLineItem> editingItems) async {
    final excludedIds = editingItems.map((line) => line.item.id).toList();
    final items = _db
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

    if (result != null && pickedItem != null && mounted) {
      context.read<SalesOrderBloc>().add(
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

  Future<void> _editLineItem(
    OrderLineItem lineItem,
    bool isEditingNew,
    String? editingOrderId,
    List<SalesOrder> orders,
  ) async {
    double originalBaseQty = 0;
    if (!isEditingNew && editingOrderId != null) {
      final originalOrderIndex = orders.indexWhere(
        (ord) => ord.id == editingOrderId,
      );
      if (originalOrderIndex >= 0) {
        final originalOrder = orders[originalOrderIndex];
        final originalLineIndex = originalOrder.items.indexWhere(
          (line) => line.item.id == lineItem.item.id,
        );
        if (originalLineIndex >= 0) {
          originalBaseQty =
              originalOrder.items[originalLineIndex].quantityInBase;
        }
      }
    }

    final result = await showDialog<ItemLineEditorResult>(
      context: context,
      builder: (context) => SharedItemLineEditorDialog(
        item: lineItem.item,
        initialQuantity: lineItem.quantity,
        originalQuantity: originalBaseQty,
        allowUnlimitedQuantity: true,
        title: 'Order Line Item Details',
        initialRate: lineItem.rate,
        initialDiscount: lineItem.discount,
        initialUom: lineItem.displayUom,
      ),
    );

    if (result != null && mounted) {
      context.read<SalesOrderBloc>().add(
        AddOrUpdateLineItem(
          item: lineItem.item,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final readOnly = _isViewMode;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<SalesOrderBloc, SalesOrderState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) {
            if (readOnly) return const Text('View Sales Order');
            return Text(
              state.isEditingNew ? 'New Sales Order' : 'Edit Sales Order',
            );
          },
        ),
        actions: [
          if (readOnly)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _isViewMode = false),
            ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<SalesOrderBloc, SalesOrderState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            if (state.successMessage == 'Sales Order saved successfully') {
              showSuccessSnackBar(context, state.successMessage!);
              context.read<SalesOrderBloc>().add(ClearMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context.read<SalesOrderBloc>().add(ClearMessages());
            }
          },
          builder: (context, state) {
            final cs = context.org.currencySymbol;
            final customer = state.editingCustomer;
            final date = state.editingDate ?? DateTime.now();
            final shipmentDate = state.editingShipmentDate ?? date;
            final tempOrder = SalesOrder(
              id: '',
              orderNumber: '',
              customerId: state.editingCustomer?.id ?? '',
              customerName: state.editingCustomer?.name ?? '',
              date: date,
              shipmentDate: shipmentDate,
              items: state.editingItems,
              notes: '',
            );
            final subtotal = tempOrder.subTotal;
            final vat = tempOrder.taxTotal;
            final discountTotal = tempOrder.discountTotal;
            final roundOff = tempOrder.roundOff;
            final total = tempOrder.total;

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
                              onTap: (!readOnly && state.isEditingNew)
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
                                                    : AppTheme
                                                          .lightTextSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (!readOnly && state.isEditingNew)
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

                          // Order date (system-set; not editable)
                          Card(
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
                                          'ORDER DATE',
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Expected Shipment Date Picker Card
                          Card(
                            child: InkWell(
                              onTap: readOnly
                                  ? null
                                  : () => _selectShipmentDate(shipmentDate),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppTheme.warningAmber
                                          .withValues(alpha: 0.1),
                                      child: const Icon(
                                        Icons.local_shipping_outlined,
                                        color: AppTheme.warningAmber,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'EXPECTED SHIPPING DATE',
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
                                            _dateFormat.format(shipmentDate),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!readOnly)
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
                              if (!readOnly)
                                TextButton.icon(
                                  onPressed: customer == null
                                      ? null
                                      : () =>
                                            _openItemSearch(state.editingItems),
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
                                      taxPercentage: line.taxPercentage
                                          .toDouble(),
                                      quantity: line.quantity,
                                      total: line.total,
                                      discount: line.discount,
                                      uom: line.displayUom,
                                    ),
                                  )
                                  .toList(),
                              currencySymbol: cs,
                              onEdit: readOnly
                                  ? null
                                  : (index) => _editLineItem(
                                      state.editingItems[index],
                                      state.isEditingNew,
                                      state.editingOrderId,
                                      state.orders,
                                    ),
                              onRemove: readOnly
                                  ? null
                                  : (index) {
                                      context.read<SalesOrderBloc>().add(
                                        RemoveLineItem(
                                          state.editingItems[index].item,
                                        ),
                                      );
                                    },
                            ),
                          const SizedBox(height: 20),

                          // Notes Field
                          TextFormField(
                            controller: _notesController,
                            maxLines: 2,
                            readOnly: readOnly,
                            enabled: !readOnly,
                            decoration: const InputDecoration(
                              labelText: 'Order Notes',
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
                  buttonLabel: readOnly ? 'CLOSE' : 'SAVE SALES ORDER',
                  buttonColor: AppTheme.primaryIndigo,
                  onSave: readOnly
                      ? () => Navigator.pop(context)
                      : (customer == null ||
                            state.editingItems.isEmpty ||
                            state.isLoading)
                      ? null
                      : () {
                          context.read<SalesOrderBloc>().add(
                            SaveOrder(notes: _notesController.text),
                          );
                        },
                  trailing: !state.isEditingNew
                      ? Builder(
                          builder: (context) {
                            final savedOrder = state.orders.firstWhere(
                              (ord) => ord.id == state.editingOrderId,
                              orElse: () => SalesOrder(
                                id: state.editingOrderId ?? '',
                                orderNumber: 'SO-TEMP',
                                customerId: customer?.id ?? '',
                                customerName: customer?.name ?? '',
                                date: date,
                                shipmentDate:
                                    state.editingDate?.add(
                                      const Duration(days: 7),
                                    ) ??
                                    DateTime.now(),
                                items: state.editingItems,
                                notes: _notesController.text,
                              ),
                            );

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Convert is available in view and edit; the
                                // converted indicator is always shown when done.
                                _buildConvertAction(context, savedOrder),
                                const SizedBox(height: 16),
                                VoucherPdfActionsWidget(
                                  type: VoucherType.salesOrder,
                                  voucher: SalesOrder(
                                    id: state.editingOrderId ?? '',
                                    orderNumber: savedOrder.orderNumber,
                                    customerId: customer?.id ?? '',
                                    customerName: customer?.name ?? '',
                                    date: date,
                                    shipmentDate: savedOrder.shipmentDate,
                                    items: state.editingItems,
                                    notes: _notesController.text,
                                    status: savedOrder.status,
                                    convertedInvoiceNumber:
                                        savedOrder.convertedInvoiceNumber,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
