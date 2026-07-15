import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/sales_return_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aggregated row for a single customer across the filtered sales returns.
class _CustomerReturnRow {
  final String customerId;
  final String customerName;
  int returnCount = 0;
  double totalRefunded = 0.0;

  _CustomerReturnRow({required this.customerId, required this.customerName});
}

enum _SortField { name, count, amount }

/// Full-screen customerwise sales-returns summary.
///
/// Fetches every sales return (credit note) live from Zoho Books and
/// aggregates them by customer, showing return count and total refunded.
/// Supports date-range filtering and column sorting.
class CustomerwiseReturnsSummaryReportPage extends StatelessWidget {
  const CustomerwiseReturnsSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<SalesReturn>>(
      create: (_) => ReportBloc<SalesReturn>(
        getLocal: () => sl<HiveDatabaseService>().getLocalReturns(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchSalesReturns();
          return raw.map((json) => SalesReturnModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      child: const _CustomerwiseReturnsSummaryReportView(),
    );
  }
}

class _CustomerwiseReturnsSummaryReportView extends StatelessWidget {
  const _CustomerwiseReturnsSummaryReportView();

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final bloc = context.read<ReportBloc<SalesReturn>>();
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

  List<_CustomerReturnRow> _buildReport(ReportState<SalesReturn> state) {
    final map = <String, _CustomerReturnRow>{};

    for (final ret in state.rows) {
      final day = DateTime(ret.date.year, ret.date.month, ret.date.day);
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
        ret.customerId,
        () => _CustomerReturnRow(
          customerId: ret.customerId,
          customerName: ret.customerName,
        ),
      );
      row.returnCount++;
      row.totalRefunded += ret.total;
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.amount;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.count:
          cmp = a.returnCount.compareTo(b.returnCount);
          break;
        case _SortField.amount:
          cmp = a.totalRefunded.compareTo(b.totalRefunded);
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

    return BlocListener<ReportBloc<SalesReturn>, ReportState<SalesReturn>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<SalesReturn>, ReportState<SalesReturn>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalReturns = rows.fold(0, (sum, r) => sum + r.returnCount);
          final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

          return SortableReportScaffold<_CustomerReturnRow, _SortField>(
            title: 'Customerwise Returns Summary',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesReturn>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.amount,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesReturn>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<SalesReturn>>().add(const SetDateRange(null, null)),
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
                field: _SortField.name,
                alignEnd: false,
              ),
              ReportColumn(label: 'RETURNS', flex: 2, field: _SortField.count),
              ReportColumn(label: 'REFUNDED', flex: 3, field: _SortField.amount),
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
      ),
    );
  }
}
