import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/utils/date_picker.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/date_range_filter_card.dart';
import '../../../../ui/core/widgets/document_list_card.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../bloc/sales_order_list_bloc.dart';
import '../bloc/sales_order_list_event.dart';
import '../bloc/sales_order_list_state.dart';
import 'sales_order_editor_page.dart';

class SalesOrderListPage extends StatefulWidget {
  const SalesOrderListPage({super.key});

  @override
  State<SalesOrderListPage> createState() => _SalesOrderListPageState();
}

class _SalesOrderListPageState extends State<SalesOrderListPage> {
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  /// Zoho `order_status` (or related fields) for a synced order, title-cased.
  /// Pending-sync local drafts omit this — only the "Pending Sync" pill shows.
  static String? _zohoStatusBadgeLabel(SalesOrder order) {
    if (order.isPendingSync) return null;

    String raw = order.orderStatus.trim();
    if (raw.isEmpty) raw = order.invoicedStatus.trim();
    if (raw.isEmpty && order.isConverted) raw = 'invoiced';

    if (raw.isEmpty) return null;
    return raw
        .split(RegExp(r'[_\s]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  static Color _zohoStatusBadgeColor(String? label) {
    switch ((label ?? '').toLowerCase()) {
      case 'invoiced':
      case 'closed':
        return AppTheme.successEmerald;
      case 'partially_invoiced':
      case 'partially invoiced':
        return AppTheme.warningAmber;
      case 'void':
      case 'cancelled':
      case 'canceled':
        return AppTheme.errorRose;
      case 'draft':
        return AppTheme.lightTextSecondary;
      case 'open':
      case 'confirmed':
        return AppTheme.infoSky;
      default:
        return AppTheme.primaryIndigo;
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<SalesOrderListBloc>().add(const LoadSalesOrders());
  }

  Future<void> _selectDate(bool isStart, DateTime? current) async {
    final picked = await showThemedDatePicker(
      context,
      initialDate: current ?? DateTime.now(),
    );
    if (picked != null && picked != current && mounted) {
      final bloc = context.read<SalesOrderListBloc>();
      if (isStart) {
        bloc.add(
          SetSalesOrderDateFilter(
            startDate: picked,
            endDate: bloc.state.endDate,
          ),
        );
      } else {
        bloc.add(
          SetSalesOrderDateFilter(
            startDate: bloc.state.startDate,
            endDate: picked,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    context.read<SalesOrderListBloc>().add(
      const SetSalesOrderDateFilter(startDate: null, endDate: null),
    );
  }

  Future<void> _openEditor({
    required bool readOnly,
    SalesOrder? order,
  }) async {
    await SalesOrderEditorPage.open<void>(
      context,
      order: order,
      readOnly: readOnly,
    );
    if (mounted) {
      // Local-only reload: a live Zoho fetch here would race the background
      // sync push the editor just fired and can clobber the just-saved edit
      // (see ReloadSalesOrdersFromCache).
      context.read<SalesOrderListBloc>().add(const ReloadSalesOrdersFromCache());
    }
  }

  /// Dispatches a refresh and waits until the list is no longer loading so
  /// [RefreshIndicator] does not dismiss while the fetch is still in flight.
  Future<void> _awaitRefresh() async {
    final bloc = context.read<SalesOrderListBloc>();
    bloc.add(const RefreshSalesOrders());
    await bloc.stream.firstWhere((s) => !s.isLoading);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Orders'),
        actions: [
          IconButton(
            tooltip: 'Sync Orders from Zoho',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context
                .read<SalesOrderListBloc>()
                .add(const RefreshSalesOrders()),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<SalesOrderListBloc, SalesOrderListState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage ||
              previous.successMessage != current.successMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context
                  .read<SalesOrderListBloc>()
                  .add(const ClearSalesOrderListMessages());
            }
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context
                  .read<SalesOrderListBloc>()
                  .add(const ClearSalesOrderListMessages());
            }
          },
          builder: (context, state) {
            final hasFilter = state.startDate != null || state.endDate != null;
            final list = state.filteredOrders;

            return Column(
              children: [
                DateRangeFilterCard(
                  startDate: state.startDate,
                  endDate: state.endDate,
                  onStartTap: () => _selectDate(true, state.startDate),
                  onEndTap: () => _selectDate(false, state.endDate),
                  onClear: _clearFilters,
                ),
                if (state.isLoading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  )
                else if (list.isEmpty)
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _awaitRefresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.6,
                            child: EmptyState(
                              icon: Icons.assignment_outlined,
                              title: 'No orders found',
                              message: hasFilter
                                  ? 'Try expanding your date range filters.'
                                  : 'Click "+" below to generate your first sales order.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: RefreshIndicator(
                          onRefresh: _awaitRefresh,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              left: 16.0,
                              right: 16.0,
                              bottom: 80.0,
                              top: 8.0,
                            ),
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final order = list[index];
                              final statusLabel =
                                  _zohoStatusBadgeLabel(order);
                              return DocumentListCard(
                                key: ValueKey(order.id),
                                docNumber: order.orderNumber,
                                customerName: order.customerName,
                                date: _dateFormat.format(order.date),
                                total: formatCurrency(order.total, cs),
                                // Remote list headers often omit line_items —
                                // only show a count when lines are known.
                                itemCount: order.items.isEmpty
                                    ? null
                                    : order.items.length,
                                isPendingSync: order.isPendingSync,
                                // Once synced: Zoho order_status (e.g. Draft).
                                extraBadgeLabel: statusLabel,
                                extraBadgeColor:
                                    _zohoStatusBadgeColor(statusLabel),
                                onTap: () => _openEditor(
                                  order: order,
                                  readOnly: true,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create New Sales Order',
        backgroundColor: AppTheme.primaryIndigo,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(readOnly: false, order: null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
