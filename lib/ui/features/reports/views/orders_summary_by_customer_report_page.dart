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

/// Aggregated row for a single customer across the filtered orders.
class _CustomerOrderRow {
  final String customerId;
  final String customerName;
  int orderCount = 0;
  double totalValue = 0.0;

  _CustomerOrderRow({required this.customerId, required this.customerName});
}

enum _SortField { name, count, value }

/// Full-screen orders-by-customer summary.
///
/// Fetches every sales order live from Zoho Books and aggregates them by
/// customer, showing order count and total value per customer. Supports
/// date-range filtering and column sorting.
class OrdersSummaryByCustomerReportPage extends StatelessWidget {
  const OrdersSummaryByCustomerReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<SalesOrder>>(
      create: (_) => ReportBloc<SalesOrder>(
        getLocal: () => sl<HiveDatabaseService>().getLocalOrders(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchSalesOrders();
          return raw.map((json) => SalesOrderModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.value,
        initialSortAscending: false,
      ),
      child: const _OrdersSummaryByCustomerReportView(),
    );
  }
}

class _OrdersSummaryByCustomerReportView extends StatelessWidget {
  const _OrdersSummaryByCustomerReportView();

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

  List<_CustomerOrderRow> _buildReport(ReportState<SalesOrder> state) {
    final map = <String, _CustomerOrderRow>{};

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

      final row = map.putIfAbsent(
        order.customerId,
        () => _CustomerOrderRow(
          customerId: order.customerId,
          customerName: order.customerName,
        ),
      );
      row.orderCount++;
      row.totalValue += order.total;
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.value;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.count:
          cmp = a.orderCount.compareTo(b.orderCount);
          break;
        case _SortField.value:
          cmp = a.totalValue.compareTo(b.totalValue);
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
          final totalOrders = rows.fold(0, (sum, r) => sum + r.orderCount);
          final totalValue = rows.fold(0.0, (sum, r) => sum + r.totalValue);

          return SortableReportScaffold<_CustomerOrderRow, _SortField>(
            title: 'Orders Summary by Customer',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesOrder>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.value,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesOrder>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<SalesOrder>>().add(const SetDateRange(null, null)),
            emptyIcon: Icons.people_outline_rounded,
            emptyTitle: 'No order data',
            emptyMessage: 'No orders recorded yet.',
            summaryChips: [
              ReportSummaryChip(
                label: 'Customers',
                value: '${rows.length}',
                color: AppTheme.infoSky,
              ),
              ReportSummaryChip(
                label: 'Orders',
                value: '$totalOrders',
                color: AppTheme.primaryIndigo,
              ),
              ReportSummaryChip(
                label: 'Total',
                value: '$cs${totalValue.toStringAsFixed(2)}',
                color: AppTheme.successEmerald,
              ),
            ],
            columns: const [
              ReportColumn(
                label: 'CUSTOMER',
                flex: 5,
                field: _SortField.name,
                alignEnd: false,
              ),
              ReportColumn(label: 'ORDERS', flex: 2, field: _SortField.count),
              ReportColumn(label: 'VALUE', flex: 3, field: _SortField.value),
            ],
            exportHeaders: const ['Customer', 'Orders', 'Value'],
            exportRow: (row) => [
              row.customerName,
              '${row.orderCount}',
              row.totalValue.toStringAsFixed(2),
            ],
            itemBuilder: (context, row) {
              final pct = totalValue > 0 ? (row.totalValue / totalValue) : 0.0;

              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(
                              row.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${row.orderCount}',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '$cs${row.totalValue.toStringAsFixed(2)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.primaryIndigo,
                              ),
                              overflow: TextOverflow.ellipsis,
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
