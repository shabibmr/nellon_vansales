import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/sales_order_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_order.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aggregated row for a single item across all filtered orders.
class _ItemOrderRow {
  final String itemId;
  final String itemName;
  final String sku;
  int totalQty = 0;
  double totalAmount = 0.0;
  final Set<String> customerIds;

  _ItemOrderRow({
    required this.itemId,
    required this.itemName,
    required this.sku,
  }) : customerIds = {};

  int get customerCount => customerIds.length;
}

enum _SortField { name, qty, amount, customers }

/// Full-screen itemwise orders summary page.
///
/// Fetches every sales order (with line items) live from Zoho Books and
/// aggregates them by item, showing total quantity ordered, total amount,
/// and number of customers per item. Supports date-range filtering and
/// column sorting.
class ItemwiseOrdersSummaryReportPage extends StatelessWidget {
  const ItemwiseOrdersSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<SalesOrder>>(
      create: (_) => ReportBloc<SalesOrder>(
        getLocal: () => sl<HiveDatabaseService>().getLocalOrders(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchSalesOrders();
          return raw.map((json) => SalesOrderModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      child: const _ItemwiseOrdersSummaryReportView(),
    );
  }
}

class _ItemwiseOrdersSummaryReportView extends StatelessWidget {
  const _ItemwiseOrdersSummaryReportView();

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final bloc = context.read<ReportBloc<SalesOrder>>();
    final current = isStart ? bloc.state.startDate : bloc.state.endDate;
    final picked = await showThemedDatePicker(context, initialDate: current);
    if (picked != null) {
      if (isStart) {
        bloc.add(SetDateRange(picked, bloc.state.endDate));
      } else {
        bloc.add(SetDateRange(bloc.state.startDate, picked));
      }
    }
  }

  List<_ItemOrderRow> _buildReport(ReportState<SalesOrder> state) {
    final map = <String, _ItemOrderRow>{};

    for (final order in state.rows) {
      final day = DateTime(order.date.year, order.date.month, order.date.day);
      if (state.startDate != null) {
        final s = DateTime(
          state.startDate!.year,
          state.startDate!.month,
          state.startDate!.day,
        );
        if (day.isBefore(s)) continue;
      }
      if (state.endDate != null) {
        final e = DateTime(state.endDate!.year, state.endDate!.month, state.endDate!.day);
        if (day.isAfter(e)) continue;
      }

      for (final line in order.items) {
        final row = map.putIfAbsent(
          line.item.id,
          () => _ItemOrderRow(
            itemId: line.item.id,
            itemName: line.item.name,
            sku: line.item.sku,
          ),
        );
        row.totalQty += line.quantity;
        row.totalAmount += line.total;
        row.customerIds.add(order.customerId);
      }
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.amount;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.name:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case _SortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
          break;
        case _SortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
        case _SortField.customers:
          cmp = a.customerCount.compareTo(b.customerCount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return BlocListener<ReportBloc<SalesOrder>, ReportState<SalesOrder>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<SalesOrder>, ReportState<SalesOrder>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalQty = rows.fold(0, (sum, r) => sum + r.totalQty);
          final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

          return SortableReportScaffold<_ItemOrderRow, _SortField>(
            title: 'Itemwise Orders Summary',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesOrder>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.amount,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesOrder>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<SalesOrder>>().add(const SetDateRange(null, null)),
            emptyIcon: Icons.shopping_cart_outlined,
            emptyTitle: 'No order data',
            emptyMessage: 'No orders recorded yet.',
            summaryChips: [
              ReportSummaryChip(
                label: 'Items',
                value: '${rows.length}',
                color: AppTheme.infoSky,
              ),
              ReportSummaryChip(
                label: 'Units Ordered',
                value: '$totalQty',
                color: AppTheme.primaryIndigo,
              ),
              ReportSummaryChip(
                label: 'Total',
                value: '$cs${totalAmount.toStringAsFixed(2)}',
                color: AppTheme.successEmerald,
              ),
            ],
            columns: const [
              ReportColumn(
                label: 'ITEM',
                flex: 5,
                field: _SortField.name,
                alignEnd: false,
              ),
              ReportColumn(label: 'QTY', flex: 2, field: _SortField.qty),
              ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
              ReportColumn(label: 'CUST', flex: 2, field: _SortField.customers),
            ],
            exportHeaders: const ['Item', 'SKU', 'Qty', 'Amount', 'Customers'],
            exportRow: (row) => [
              row.itemName,
              row.sku,
              '${row.totalQty}',
              row.totalAmount.toStringAsFixed(2),
              '${row.customerCount}',
            ],
            itemBuilder: (context, row) {
              final pct = totalAmount > 0 ? (row.totalAmount / totalAmount) : 0.0;

              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.itemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'SKU: ${row.sku}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${row.totalQty}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '$cs${row.totalAmount.toStringAsFixed(2)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.primaryIndigo,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${row.customerCount}',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE2E8F0),
                          color: AppTheme.primaryIndigo,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
