import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/sales_return_model.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_filter.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

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

  List<_CustomerReturnRow> _buildReport(ReportState<SalesReturn> state) {
    final map = <String, _CustomerReturnRow>{};

    final filtered = filterByDateRange(
      state.rows,
      (ret) => ret.date,
      startDate: state.startDate,
      endDate: state.endDate,
    );
    for (final ret in filtered) {
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
      return state.sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesReturn>(
      create: (_) => ReportBloc<SalesReturn>(
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchSalesReturns();
          return raw.map((json) => SalesReturnModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = _buildReport(state);
        final totalReturns = rows.fold(0, (sum, r) => sum + r.returnCount);
        final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

        return SortableReportScaffold<_CustomerReturnRow, _SortField>(
          title: 'Customerwise Returns Summary',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<SalesReturn>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField: state.sortField as _SortField? ?? _SortField.amount,
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
    );
  }
}
