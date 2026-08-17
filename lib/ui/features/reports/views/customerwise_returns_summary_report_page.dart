import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/customerwise_returns_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen customerwise sales-returns summary.
///
/// Fetches every sales return (credit note) and aggregates them by customer,
/// showing return count and total refunded. Supports date-range filtering
/// and column sorting.
class CustomerwiseReturnsSummaryReportPage extends StatelessWidget {
  const CustomerwiseReturnsSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesReturn>(
      create: (_) => ReportBloc<SalesReturn>(
        fetchRemote: () => context.read<ReportRepository>().fetchSalesReturns(),
        initialSortField: CustomerwiseReturnsSortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final sortField = state.sortField as CustomerwiseReturnsSortField? ??
            CustomerwiseReturnsSortField.amount;
        final rows = CustomerwiseReturnsAggregator.aggregate(
          returns: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField: sortField,
          sortAscending: state.sortAscending,
        );
        final totalReturns = rows.fold(0, (sum, r) => sum + r.returnCount);
        final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

        return SortableReportScaffold<CustomerwiseReturnsRow, CustomerwiseReturnsSortField>(
          title: 'Customerwise Returns Summary',
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
              label: 'Customers',
              value: '${rows.length}',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Returns',
              value: '$totalReturns',
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
              label: 'CUSTOMER',
              flex: 5,
              field: CustomerwiseReturnsSortField.name,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'RETURNS',
              flex: 2,
              field: CustomerwiseReturnsSortField.count,
            ),
            ReportColumn(
              label: 'REFUNDED',
              flex: 3,
              field: CustomerwiseReturnsSortField.amount,
            ),
          ],
          exportHeaders: const ['Customer', 'Returns', 'Refunded'],
          exportRow: (row) => [
            row.customerName,
            '${row.returnCount}',
            row.totalRefunded.toStringAsFixed(2),
          ],
          itemBuilder: (context, row) {
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
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
                        '${row.returnCount}',
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

