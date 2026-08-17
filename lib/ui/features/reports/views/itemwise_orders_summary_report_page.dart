import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/sales_order.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/itemwise_orders_summary_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen itemwise orders summary page.
///
/// Fetches sales orders (with line items) via [ReportRepository] and
/// aggregates them by item using [ItemwiseOrdersSummaryAggregator], showing total quantity ordered,
/// total amount, and number of customers per item. Supports date-range filtering and
/// column sorting.
class ItemwiseOrdersSummaryReportPage extends StatelessWidget {
  const ItemwiseOrdersSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesOrder>(
      create: (_) => ReportBloc<SalesOrder>(
        fetchRemote: () => context.read<ReportRepository>().fetchSalesOrders(),
        initialSortField: ItemwiseOrdersSummarySortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = ItemwiseOrdersSummaryAggregator.aggregate(
          orders: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField:
              state.sortField as ItemwiseOrdersSummarySortField? ??
              ItemwiseOrdersSummarySortField.amount,
          sortAscending: state.sortAscending,
        );
        final totalQty = rows.fold(0.0, (sum, r) => sum + r.totalQty);
        final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

        return SortableReportScaffold<
          ItemwiseOrdersSummaryRow,
          ItemwiseOrdersSummarySortField
        >(
          title: 'Itemwise Orders Summary',
          isLoading: state.isLoading,
          onRefresh: () =>
              context.read<ReportBloc<SalesOrder>>().add(const RefreshReport()),
          rows: rows,
          sortField:
              state.sortField as ItemwiseOrdersSummarySortField? ??
              ItemwiseOrdersSummarySortField.amount,
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
              value: formatQuantity(totalQty),
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
              field: ItemwiseOrdersSummarySortField.name,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'QTY',
              flex: 2,
              field: ItemwiseOrdersSummarySortField.qty,
            ),
            ReportColumn(
              label: 'AMOUNT',
              flex: 3,
              field: ItemwiseOrdersSummarySortField.amount,
            ),
            ReportColumn(
              label: 'CUST',
              flex: 2,
              field: ItemwiseOrdersSummarySortField.customers,
            ),
          ],
          exportHeaders: const ['Item', 'SKU', 'Qty', 'Amount', 'Customers'],
          exportRow: (row) => [
            row.itemName,
            row.sku,
            formatQuantity(row.totalQty),
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
                            formatQuantity(row.totalQty),
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
    );
  }
}
