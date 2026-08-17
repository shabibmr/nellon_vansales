import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/orders_summary_by_customer_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen orders-by-customer summary.
///
/// Fetches sales orders via [ReportRepository] and aggregates them by
/// customer using [OrdersSummaryByCustomerAggregator], showing order count
/// and total value per customer. Supports date-range filtering and column sorting.
class OrdersSummaryByCustomerReportPage extends StatelessWidget {
  const OrdersSummaryByCustomerReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesOrder>(
      create: (_) => ReportBloc<SalesOrder>(
        fetchRemote: () => context.read<ReportRepository>().fetchSalesOrders(),
        initialSortField: OrdersSummaryByCustomerSortField.value,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = OrdersSummaryByCustomerAggregator.aggregate(
          orders: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField:
              state.sortField as OrdersSummaryByCustomerSortField? ??
              OrdersSummaryByCustomerSortField.value,
          sortAscending: state.sortAscending,
        );
        final totalOrders = rows.fold(0, (sum, r) => sum + r.orderCount);
        final totalValue = rows.fold(0.0, (sum, r) => sum + r.totalValue);

        return SortableReportScaffold<
          OrdersSummaryByCustomerRow,
          OrdersSummaryByCustomerSortField
        >(
          title: 'Orders Summary by Customer',
          isLoading: state.isLoading,
          onRefresh: () =>
              context.read<ReportBloc<SalesOrder>>().add(const RefreshReport()),
          rows: rows,
          sortField:
              state.sortField as OrdersSummaryByCustomerSortField? ??
              OrdersSummaryByCustomerSortField.value,
          sortAscending: state.sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<SalesOrder>>().add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () => pickReportDate<SalesOrder>(context, true),
          onEndDateTap: () => pickReportDate<SalesOrder>(context, false),
          onClearDate: () => context.read<ReportBloc<SalesOrder>>().add(
            const SetDateRange(null, null),
          ),
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
              field: OrdersSummaryByCustomerSortField.name,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'ORDERS',
              flex: 2,
              field: OrdersSummaryByCustomerSortField.count,
            ),
            ReportColumn(
              label: 'VALUE',
              flex: 3,
              field: OrdersSummaryByCustomerSortField.value,
            ),
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
    );
  }
}
