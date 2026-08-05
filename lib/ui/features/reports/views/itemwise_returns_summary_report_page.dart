import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/itemwise_returns_summary_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen itemwise sales-returns summary.
///
/// Fetches every sales return (credit note, with line items) via [ReportRepository]
/// and aggregates them by item using [ItemwiseReturnsSummaryAggregator], showing
/// quantity returned and total refunded. Supports date-range filtering and column sorting.
class ItemwiseReturnsSummaryReportPage extends StatelessWidget {
  const ItemwiseReturnsSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesReturn>(
      create: (_) => ReportBloc<SalesReturn>(
        fetchRemote: () => sl<ReportRepository>().fetchSalesReturns(),
        initialSortField: ItemwiseReturnsSummarySortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final sortField =
            state.sortField as ItemwiseReturnsSummarySortField? ??
            ItemwiseReturnsSummarySortField.amount;
        final rows = ItemwiseReturnsSummaryAggregator.aggregate(
          returns: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField: sortField,
          sortAscending: state.sortAscending,
        );
        final totalQty = rows.fold(0.0, (sum, r) => sum + r.totalQty);
        final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

        return SortableReportScaffold<
          ItemwiseReturnsSummaryRow,
          ItemwiseReturnsSummarySortField
        >(
          title: 'Itemwise Returns Summary',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<SalesReturn>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField: sortField,
          sortAscending: state.sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<SalesReturn>>().add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () => pickReportDate<SalesReturn>(context, true),
          onEndDateTap: () => pickReportDate<SalesReturn>(context, false),
          onClearDate: () => context.read<ReportBloc<SalesReturn>>().add(
            const SetDateRange(null, null),
          ),
          emptyIcon: Icons.assignment_return_outlined,
          emptyTitle: 'No return data',
          emptyMessage: 'No sales returns recorded yet.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Items',
              value: '${rows.length}',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Units Returned',
              value: formatQuantity(totalQty),
              color: AppTheme.warningAmber,
            ),
            ReportSummaryChip(
              label: 'Total Refunded',
              value: '$cs${totalRefunded.toStringAsFixed(2)}',
              color: AppTheme.errorRose,
            ),
          ],
          columns: const [
            ReportColumn(
              label: 'ITEM',
              flex: 5,
              field: ItemwiseReturnsSummarySortField.name,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'QTY',
              flex: 2,
              field: ItemwiseReturnsSummarySortField.qty,
            ),
            ReportColumn(
              label: 'REFUNDED',
              flex: 3,
              field: ItemwiseReturnsSummarySortField.amount,
            ),
          ],
          exportHeaders: const ['Item', 'SKU', 'Qty', 'Refunded'],
          exportRow: (row) => [
            row.itemName,
            row.sku,
            formatQuantity(row.totalQty),
            row.totalRefunded.toStringAsFixed(2),
          ],
          itemBuilder: (context, row) {
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
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
                        '$cs${row.totalRefunded.toStringAsFixed(2)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.errorRose,
                        ),
                        overflow: TextOverflow.ellipsis,
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
