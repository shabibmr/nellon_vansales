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
  const SalesOrderEditorPage({super.key});

  @override
  State<SalesOrderEditorPage> createState() => _SalesOrderEditorPageState();
}

class _SalesOrderEditorPageState extends State<SalesOrderEditorPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  late TextEditingController _notesController;
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  @override
  void initState() {
    super.initState();
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

  Future<void> _selectOrderDate(DateTime currentDate) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: currentDate,
    );
    if (picked != null && mounted) {
      context.read<SalesOrderBloc>().add(UpdateOrderDate(picked));
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

    (Item, int, double, double)? result;
    await ItemSearchSheet.show<void>(
      context,
      items: items,
      title: 'Search Items',
      emptyMessage: 'No items in van stock',
      onSelected: (item, sheetContext) async {
        final editorResult = await showDialog<(int, double, double)>(
          context: sheetContext,
          builder: (context) => SharedItemLineEditorDialog(
            item: item,
            allowUnlimitedQuantity: true,
            title: 'Order Line Item Details',
          ),
        );
        if (editorResult != null) {
          final (qty, rate, discount) = editorResult;
          if (qty > 0) {
            result = (item, qty, rate, discount);
            if (sheetContext.mounted) Navigator.pop(sheetContext, null);
          }
        }
      },
    );

    if (result != null && mounted) {
      final (item, qty, rate, discount) = result!;
      context.read<SalesOrderBloc>().add(
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
    OrderLineItem lineItem,
    bool isEditingNew,
    String? editingOrderId,
    List<SalesOrder> orders,
  ) async {
    int originalQty = 0;
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
          originalQty = originalOrder.items[originalLineIndex].quantity;
        }
      }
    }

    final result = await showDialog<(int, double, double)>(
      context: context,
      builder: (context) => SharedItemLineEditorDialog(
        item: lineItem.item,
        initialQuantity: lineItem.quantity,
        originalQuantity: originalQty,
        allowUnlimitedQuantity: true,
        title: 'Order Line Item Details',
        initialRate: lineItem.rate,
        initialDiscount: lineItem.discount,
      ),
    );

    if (result != null && mounted) {
      final (newQty, newRate, newDiscount) = result;
      context.read<SalesOrderBloc>().add(
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
        title: BlocBuilder<SalesOrderBloc, SalesOrderState>(
          buildWhen: (previous, current) =>
              previous.isEditingNew != current.isEditingNew,
          builder: (context, state) =>
              Text(state.isEditingNew ? 'New Sales Order' : 'Edit Sales Order'),
        ),
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
            final tempOrder = SalesOrder(
              id: '',
              orderNumber: '',
              customerId: state.editingCustomer?.id ?? '',
              customerName: state.editingCustomer?.name ?? '',
              date: state.editingDate ?? DateTime.now(),
              shipmentDate: state.editingDate ?? DateTime.now(),
              items: state.editingItems,
              notes: '',
            );
            final subtotal = tempOrder.subTotal;
            final vat = tempOrder.taxTotal;
            final discountTotal = tempOrder.discountTotal;
            final roundOff = tempOrder.roundOff;
            final total = tempOrder.total;
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
                                                    : AppTheme
                                                          .lightTextSecondary,
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
                              onTap: () => _selectOrderDate(date),
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
                                      taxPercentage: line.taxPercentage
                                          .toDouble(),
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
                                state.editingOrderId,
                                state.orders,
                              ),
                              onRemove: (index) {
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
                  buttonLabel: 'SAVE SALES ORDER',
                  buttonColor: AppTheme.primaryIndigo,
                  onSave:
                      (customer == null ||
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
                                    shipmentDate:
                                        state.editingDate?.add(
                                          const Duration(days: 7),
                                        ) ??
                                        DateTime.now(),
                                    items: state.editingItems,
                                    notes: _notesController.text,
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
