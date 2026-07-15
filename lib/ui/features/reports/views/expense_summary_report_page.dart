import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aggregated row for a single expense category across the filtered period.
class _CategoryRow {
  final String category;
  int entryCount = 0;
  double totalAmount = 0.0;

  _CategoryRow({required this.category});
}

enum _SortField { category, count, amount }

/// Full-screen expense summary, grouped by ledger category.
///
/// Fetches every expense (with itemized lines) live from Zoho Books and
/// aggregates them by category, showing entry count and total amount per
/// category. Supports date-range filtering and column sorting. The local
/// expense cache is painted instantly on open while the live fetch is in
/// flight.
class ExpenseSummaryReportPage extends StatelessWidget {
  const ExpenseSummaryReportPage({super.key});

  static Map<String, dynamic> _normalizeExpenseJson(Map<String, dynamic> json) {
    final lineItems = (json['line_items'] as List?) ?? const [];
    return {
      ...json,
      'lines': lineItems
          .whereType<Map>()
          .map(
            (l) => {
              'category': l['account_name'] ?? 'Miscellaneous',
              'amount': l['amount'] ?? 0.0,
              'description': l['description'] ?? '',
            },
          )
          .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<ExpenseEntry>>(
      create: (_) => ReportBloc<ExpenseEntry>(
        getLocal: () => sl<HiveDatabaseService>().getLocalExpenses(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchExpenses();
          return raw
              .map((json) => ExpenseEntryModel.fromJson(_normalizeExpenseJson(json)))
              .toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      child: const _ExpenseSummaryReportView(),
    );
  }
}

class _ExpenseSummaryReportView extends StatelessWidget {
  const _ExpenseSummaryReportView();

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final bloc = context.read<ReportBloc<ExpenseEntry>>();
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

  List<_CategoryRow> _buildReport(ReportState<ExpenseEntry> state) {
    final map = <String, _CategoryRow>{};

    for (final entry in state.rows) {
      final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
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

      for (final line in entry.lines) {
        final row = map.putIfAbsent(
          line.category,
          () => _CategoryRow(category: line.category),
        );
        row.entryCount++;
        row.totalAmount += line.amount;
      }
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.amount;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.category:
          cmp = a.category.compareTo(b.category);
          break;
        case _SortField.count:
          cmp = a.entryCount.compareTo(b.entryCount);
          break;
        case _SortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;

    return BlocListener<ReportBloc<ExpenseEntry>, ReportState<ExpenseEntry>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<ExpenseEntry>, ReportState<ExpenseEntry>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalCount = rows.fold(0, (sum, r) => sum + r.entryCount);
          final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

          return SortableReportScaffold<_CategoryRow, _SortField>(
            title: 'Expense Summary',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<ExpenseEntry>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.amount,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<ExpenseEntry>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<ExpenseEntry>>().add(const SetDateRange(null, null)),
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
                field: _SortField.category,
                alignEnd: false,
              ),
              ReportColumn(label: 'ENTRIES', flex: 2, field: _SortField.count),
              ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
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
      ),
    );
  }
}
