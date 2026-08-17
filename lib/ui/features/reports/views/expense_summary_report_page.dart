import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/expense_summary_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen expense summary, grouped by ledger category.
///
/// Fetches every expense (with itemized lines) and aggregates them by category,
/// showing entry count and total amount per category. Supports date-range
/// filtering and column sorting.
class ExpenseSummaryReportPage extends StatelessWidget {
  const ExpenseSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return ReportBlocHost<ExpenseEntry>(
      create: (_) => ReportBloc<ExpenseEntry>(
        fetchRemote: () => context.read<ReportRepository>().fetchExpenses(),
        initialSortField: ExpenseSummarySortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final sortField = state.sortField as ExpenseSummarySortField? ??
            ExpenseSummarySortField.amount;
        final rows = ExpenseSummaryAggregator.aggregate(
          expenses: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField: sortField,
          sortAscending: state.sortAscending,
        );
        final totalCount = rows.fold(0, (sum, r) => sum + r.entryCount);
        final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

        return SortableReportScaffold<ExpenseSummaryCategoryRow, ExpenseSummarySortField>(
          title: 'Expense Summary',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<ExpenseEntry>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField: sortField,
          sortAscending: state.sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<ExpenseEntry>>().add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () => pickReportDate<ExpenseEntry>(context, true),
          onEndDateTap: () => pickReportDate<ExpenseEntry>(context, false),
          onClearDate: () => context.read<ReportBloc<ExpenseEntry>>().add(
            const SetDateRange(null, null),
          ),
          emptyIcon: Icons.receipt_long_outlined,
          emptyTitle: 'No expenses',
          emptyMessage: 'No expenses recorded yet.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Categories',
              value: '${rows.length}',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Entries',
              value: '$totalCount',
              color: AppTheme.primaryIndigo,
            ),
            ReportSummaryChip(
              label: 'Total',
              value: '$cs${totalAmount.toStringAsFixed(2)}',
              color: AppTheme.errorRose,
            ),
          ],
          columns: const [
            ReportColumn(
              label: 'CATEGORY',
              flex: 5,
              field: ExpenseSummarySortField.category,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'ENTRIES',
              flex: 2,
              field: ExpenseSummarySortField.count,
            ),
            ReportColumn(
              label: 'AMOUNT',
              flex: 3,
              field: ExpenseSummarySortField.amount,
            ),
          ],
          exportHeaders: const ['Category', 'Entries', 'Amount'],
          exportRow: (row) => [
            row.category,
            '${row.entryCount}',
            row.totalAmount.toStringAsFixed(2),
          ],
          itemBuilder: (context, row) {
            final pct = totalAmount > 0 ? (row.totalAmount / totalAmount) : 0.0;
            final isDark = Theme.of(context).brightness == Brightness.dark;

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
                            row.category,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${row.entryCount}',
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
                            '$cs${row.totalAmount.toStringAsFixed(2)}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.errorRose,
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
                        color: AppTheme.errorRose,
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

