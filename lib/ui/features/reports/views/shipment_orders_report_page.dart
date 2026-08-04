import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/services/injection.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/date_range_filter_card.dart';
import '../../../core/widgets/document_list_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_pill.dart';
import '../../sales_invoice/bloc/sales_invoice_list_bloc.dart' as inv;
import '../../sales_invoice/bloc/sales_invoice_list_event.dart' as inv;
import '../../sales_invoice/bloc/sales_invoice_list_state.dart' as inv;
import '../../sales_order/views/sales_order_editor_page.dart';
import '../../stock_transfer/bloc/stock_transfer_bloc.dart'
    hide ClearMessages;
import '../../stock_transfer/views/issue_to_van_page.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../bloc/shipment_orders_cubit.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Shipment-day workspace: filter sales orders by shipment date, multi-select
/// for batch convert-to-invoice, and item demand → Issue-to-Van handoff.
class ShipmentOrdersReportPage extends StatelessWidget {
  const ShipmentOrdersReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportBlocHost<SalesOrder>(
      create: (_) => ReportBloc<SalesOrder>(
        fetchRemote: () => sl<SalesRepository>().fetchRemoteOrders(),
      ),
      builder: (context, reportState) {
        return BlocProvider(
          create: (_) => ShipmentOrdersCubit(),
          child: DefaultTabController(
            length: 2,
            child: _ShipmentOrdersReportBody(reportState: reportState),
          ),
        );
      },
    );
  }
}

class _ShipmentOrdersReportBody extends StatelessWidget {
  final ReportState<SalesOrder> reportState;

  const _ShipmentOrdersReportBody({required this.reportState});

  List<SalesOrder> _filteredOrders() {
    return filterOrdersByShipmentDate(
      reportState.rows,
      startDate: reportState.startDate,
      endDate: reportState.endDate,
    );
  }

  Color _statusColor(ShipmentOrderStatus status) {
    return switch (status) {
      ShipmentOrderStatus.open => AppTheme.infoSky,
      ShipmentOrderStatus.delayed => AppTheme.errorRose,
      ShipmentOrderStatus.invoiced => AppTheme.successEmerald,
    };
  }

  Future<void> _openOrderView(BuildContext context, SalesOrder order) async {
    await SalesOrderEditorPage.open(
      context,
      order: order,
      readOnly: true,
    );
  }

  Future<void> _confirmAndConvert(
    BuildContext context,
    List<SalesOrder> selected,
  ) async {
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Invoice'),
        content: Text(
          'Create one invoice for each of the ${selected.length} selected '
          'open order${selected.length == 1 ? '' : 's'}?\n\n'
          'Ensure van stock is loaded first if needed (Items → Create Stock Transfer).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    context.read<inv.SalesInvoiceListBloc>().add(inv.ConvertOrdersBatch(selected));
  }

  void _openStockTransfer(
    BuildContext context,
    List<ShipmentItemSummary> items,
  ) {
    final demand = demandMapFromSummaries(items);
    if (demand.isEmpty) {
      showErrorSnackBar(context, 'No item quantities to transfer');
      return;
    }
    context.read<StockTransferBloc>().add(LoadIssueGridWithDemand(demand));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IssueToVanPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final dateFmt = DateFormat('dd MMM yyyy');
    final filtered = _filteredOrders();
    final itemRows = aggregateItemsFromOrders(filtered);

    return BlocListener<inv.SalesInvoiceListBloc, inv.SalesInvoiceListState>(
      listenWhen: (prev, curr) =>
          prev.successMessage != curr.successMessage ||
          prev.errorMessage != curr.errorMessage ||
          prev.isLoading != curr.isLoading,
      listener: (context, invState) {
        if (invState.successMessage != null) {
          showSuccessSnackBar(context, invState.successMessage!);
          context.read<inv.SalesInvoiceListBloc>().add(const inv.ClearInvoiceListMessages());
          context.read<ShipmentOrdersCubit>().clearSelection();
          context.read<ReportBloc<SalesOrder>>().add(const RefreshReport());
        } else if (invState.errorMessage != null) {
          showErrorSnackBar(context, invState.errorMessage!);
          context.read<inv.SalesInvoiceListBloc>().add(const inv.ClearInvoiceListMessages());
          context.read<ReportBloc<SalesOrder>>().add(const RefreshReport());
        }
      },
      child: BlocBuilder<ShipmentOrdersCubit, ShipmentOrdersSelectionState>(
        builder: (context, selection) {
          final selectedOrders = context
              .read<ShipmentOrdersCubit>()
              .selectedOrders(filtered);
          final converting = context
              .watch<inv.SalesInvoiceListBloc>()
              .state
              .isLoading;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Orders by Shipment Date'),
              actions: [
                if (reportState.isLoading || converting)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => context
                        .read<ReportBloc<SalesOrder>>()
                        .add(const RefreshReport()),
                  ),
                IconButton(
                  tooltip: 'Select all open',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () => context
                      .read<ShipmentOrdersCubit>()
                      .selectAllOpen(filtered),
                ),
                if (selection.selectedCount > 0)
                  IconButton(
                    tooltip: 'Clear selection',
                    icon: const Icon(Icons.deselect_rounded),
                    onPressed: () =>
                        context.read<ShipmentOrdersCubit>().clearSelection(),
                  ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Orders'),
                  Tab(text: 'Items'),
                ],
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  DateRangeFilterCard(
                    startDate: reportState.startDate,
                    endDate: reportState.endDate,
                    onStartTap: () => pickReportDate<SalesOrder>(context, true),
                    onEndTap: () => pickReportDate<SalesOrder>(context, false),
                    onClear: () => context.read<ReportBloc<SalesOrder>>().add(
                      const SetDateRange(null, null),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Filtered by shipment date · ${filtered.length} order${filtered.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _OrdersTab(
                          orders: filtered,
                          isLoading: reportState.isLoading,
                          dateFmt: dateFmt,
                          currencySymbol: cs,
                          isDark: isDark,
                          selection: selection,
                          statusColor: _statusColor,
                          onToggle: (id) =>
                              context.read<ShipmentOrdersCubit>().toggle(id),
                          onOpen: (order) => _openOrderView(context, order),
                        ),
                        _ItemsTab(
                          items: itemRows,
                          currencySymbol: cs,
                          isDark: isDark,
                          onCreateStockTransfer: () =>
                              _openStockTransfer(context, itemRows),
                        ),
                      ],
                    ),
                  ),
                  if (selectedOrders.isNotEmpty)
                    SafeArea(
                      top: false,
                      child: Material(
                        elevation: 8,
                        color: isDark
                            ? AppTheme.darkSurface
                            : AppTheme.lightSurface,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: converting
                                  ? null
                                  : () => _confirmAndConvert(
                                      context,
                                      selectedOrders,
                                    ),
                              icon: converting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.receipt_long),
                              label: Text(
                                'CONVERT TO INVOICE (${selectedOrders.length})',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryIndigo,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  final List<SalesOrder> orders;
  final bool isLoading;
  final DateFormat dateFmt;
  final String currencySymbol;
  final bool isDark;
  final ShipmentOrdersSelectionState selection;
  final Color Function(ShipmentOrderStatus) statusColor;
  final void Function(String id) onToggle;
  final void Function(SalesOrder order) onOpen;

  const _OrdersTab({
    required this.orders,
    required this.isLoading,
    required this.dateFmt,
    required this.currencySymbol,
    required this.isDark,
    required this.selection,
    required this.statusColor,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No orders for this shipment range',
        message: 'Adjust the shipment date filter or create sales orders.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final order = orders[index];
        final status = classifyOrderStatus(order);
        final selectable = !order.isConverted;
        final selected = selection.isSelected(order.id);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              Padding(
                padding: const EdgeInsets.only(top: 20, right: 4),
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onToggle(order.id),
                  activeColor: AppTheme.primaryIndigo,
                ),
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: DocumentListCard(
                docNumber: order.orderNumber,
                customerName: order.customerName,
                date: dateFmt.format(order.date),
                subtitle: 'Ship: ${dateFmt.format(order.shipmentDate)}',
                total: formatCurrency(order.total, currencySymbol),
                itemCount: order.items.length,
                isPendingSync: order.isPendingSync,
                extraBadgeLabel: shipmentOrderStatusLabel(status),
                extraBadgeColor: statusColor(status),
                accentColor: selected
                    ? AppTheme.primaryIndigo
                    : AppTheme.primaryIndigo,
                onTap: () => onOpen(order),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ItemsTab extends StatelessWidget {
  final List<ShipmentItemSummary> items;
  final String currencySymbol;
  final bool isDark;
  final VoidCallback onCreateStockTransfer;

  const _ItemsTab({
    required this.items,
    required this.currencySymbol,
    required this.isDark,
    required this.onCreateStockTransfer,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No items in range',
        message: 'Orders matching the shipment filter have no line items.',
      );
    }

    final totalQty = items.fold<double>(0, (s, r) => s + r.totalQty);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              StatusPill(
                label: '${items.length} items',
                color: AppTheme.infoSky,
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: '${formatQuantity(totalQty)} units',
                color: AppTheme.primaryIndigo,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: onCreateStockTransfer,
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Create Stock Transfer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successEmerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = items[index];
              return Card(
                child: ListTile(
                  title: Text(
                    row.itemName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'SKU: ${row.sku} · ${row.orderCount} order${row.orderCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Qty ${formatQuantity(row.totalQty)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        formatCurrency(row.totalAmount, currencySymbol),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryIndigo,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
