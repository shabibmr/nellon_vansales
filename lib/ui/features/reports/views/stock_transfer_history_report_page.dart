import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/stock_transfer_history_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen stock transfer history report — Issue to Van and Stock
/// Unloading vouchers, scoped to the logged-in salesperson's van
/// (`ZohoApiClient.fetchStockTransfers` filters by from/to location).
class StockTransferHistoryReportPage extends StatelessWidget {
  const StockTransferHistoryReportPage({super.key});

  static (String, IconData, Color) _directionStyle(
    StockTransferDirection direction,
  ) {
    return switch (direction) {
      StockTransferDirection.load => (
        'Issue to Van',
        Icons.upload_rounded,
        AppTheme.successEmerald,
      ),
      StockTransferDirection.unload => (
        'Stock Unloading',
        Icons.download_rounded,
        AppTheme.warningAmber,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ReportBlocHost<StockTransfer>(
      create: (_) => ReportBloc<StockTransfer>(
        fetchRemote: () => context.read<ReportRepository>().fetchStockTransfers(),
        initialSortField: StockTransferHistorySortField.date,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final sortField =
            state.sortField as StockTransferHistorySortField? ??
            StockTransferHistorySortField.date;

        final rows = StockTransferHistoryAggregator.aggregate(
          transfers: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField: sortField,
          sortAscending: state.sortAscending,
        );

        final loadCount = rows
            .where((t) => t.direction == StockTransferDirection.load)
            .length;
        final unloadCount = rows.length - loadCount;

        return SortableReportScaffold<
          StockTransfer,
          StockTransferHistorySortField
        >(
          title: 'Stock Transfer History',
          isLoading: state.isLoading,
          onRefresh: () => context
              .read<ReportBloc<StockTransfer>>()
              .add(const RefreshReport()),
          rows: rows,
          sortField: sortField,
          sortAscending: state.sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<StockTransfer>>().add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () =>
              pickReportDate<StockTransfer>(context, true),
          onEndDateTap: () =>
              pickReportDate<StockTransfer>(context, false),
          onClearDate: () => context
              .read<ReportBloc<StockTransfer>>()
              .add(const SetDateRange(null, null)),
          emptyIcon: Icons.local_shipping_outlined,
          emptyTitle: 'No transfers',
          emptyMessage:
              'No Issue to Van or Stock Unloading transfers recorded yet.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Issue to Van',
              value: '$loadCount',
              color: AppTheme.successEmerald,
            ),
            ReportSummaryChip(
              label: 'Stock Unloading',
              value: '$unloadCount',
              color: AppTheme.warningAmber,
            ),
          ],
          columns: const [
            ReportColumn(
              label: 'TRANSFER',
              flex: 4,
              field: StockTransferHistorySortField.transferNumber,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'DIRECTION',
              flex: 3,
              field: StockTransferHistorySortField.direction,
            ),
            ReportColumn(
              label: 'DATE',
              flex: 3,
              field: StockTransferHistorySortField.date,
            ),
          ],
          exportHeaders: const [
            'Date',
            'Transfer Number',
            'Direction',
            'Item Count',
            'Notes',
          ],
          exportRow: (transfer) {
            final (label, _, _) = _directionStyle(transfer.direction);
            return [
              DateFormat('dd MMM yyyy').format(transfer.date),
              transfer.transferNumber,
              label,
              '${transfer.lines.length}',
              transfer.notes,
            ];
          },
          itemBuilder: (context, transfer) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final (label, icon, color) = _directionStyle(transfer.direction);
            return Card(
              margin: EdgeInsets.zero,
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  child: Icon(icon, color: color, size: 20),
                ),
                title: Text(
                  transfer.transferNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '$label · ${DateFormat('dd MMM yyyy').format(transfer.date)} · '
                  '${transfer.lines.length} item(s)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                children: [
                  for (final line in transfer.lines)
                    ListTile(
                      dense: true,
                      title: Text(line.item.name),
                      trailing: Text(
                        '${formatQuantity(line.enteredQuantity)} '
                        '${line.uom.isNotEmpty ? line.uom : line.item.uom}',
                      ),
                    ),
                  if (transfer.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        transfer.notes,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
