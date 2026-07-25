import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_filter.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Aggregated row for a single payment mode across the filtered period.
class _ModeRow {
  final String mode;
  int receiptCount = 0;
  double totalCollected = 0.0;
  double totalAllocated = 0.0;
  double totalUnallocated = 0.0;

  _ModeRow({required this.mode});
}

enum _SortField { mode, count, collected }

/// Full-screen invoice receipts summary, grouped by payment mode.
///
/// Fetches every customer payment (receipt) live from Zoho Books and
/// aggregates by payment mode, showing receipt count, total collected,
/// total applied to invoices, and total left unallocated (customer credit).
class InvoiceReceiptsSummaryReportPage extends StatelessWidget {
  const InvoiceReceiptsSummaryReportPage({super.key});

  List<_ModeRow> _buildReport(ReportState<ReceiptVoucher> state) {
    final map = <String, _ModeRow>{};

    final filtered = filterByDateRange(
      state.rows,
      (rcpt) => rcpt.date,
      startDate: state.startDate,
      endDate: state.endDate,
    );
    for (final rcpt in filtered) {
      final row = map.putIfAbsent(
        rcpt.paymentMode,
        () => _ModeRow(mode: rcpt.paymentMode),
      );
      row.receiptCount++;
      row.totalCollected += rcpt.amount;
      row.totalAllocated += rcpt.totalAllocated;
      row.totalUnallocated += rcpt.unallocatedAmount;
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.collected;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.mode:
          cmp = a.mode.compareTo(b.mode);
          break;
        case _SortField.count:
          cmp = a.receiptCount.compareTo(b.receiptCount);
          break;
        case _SortField.collected:
          cmp = a.totalCollected.compareTo(b.totalCollected);
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

    return ReportBlocHost<ReceiptVoucher>(
      create: (_) => ReportBloc<ReceiptVoucher>(
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchReceipts();
          return raw.map((json) => ReceiptVoucherModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.collected,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = _buildReport(state);
        final totalCount = rows.fold(0, (sum, r) => sum + r.receiptCount);
        final totalCollected = rows.fold(
          0.0,
          (sum, r) => sum + r.totalCollected,
        );

        return SortableReportScaffold<_ModeRow, _SortField>(
          title: 'Invoice Receipts Summary',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<ReceiptVoucher>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField: state.sortField as _SortField? ?? _SortField.collected,
          sortAscending: state.sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<ReceiptVoucher>>().add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () => pickReportDate<ReceiptVoucher>(context, true),
          onEndDateTap: () => pickReportDate<ReceiptVoucher>(context, false),
          onClearDate: () => context.read<ReportBloc<ReceiptVoucher>>().add(
            const SetDateRange(null, null),
          ),
          emptyIcon: Icons.account_balance_wallet_outlined,
          emptyTitle: 'No receipts',
          emptyMessage: 'No receipts recorded yet.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Receipts',
              value: '$totalCount',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Total Collected',
              value: '$cs${totalCollected.toStringAsFixed(2)}',
              color: AppTheme.successEmerald,
            ),
          ],
          columns: const [
            ReportColumn(
              label: 'MODE',
              flex: 4,
              field: _SortField.mode,
              alignEnd: false,
            ),
            ReportColumn(label: 'COUNT', flex: 2, field: _SortField.count),
            ReportColumn(
              label: 'COLLECTED',
              flex: 4,
              field: _SortField.collected,
            ),
          ],
          exportHeaders: const [
            'Mode',
            'Count',
            'Collected',
            'Allocated',
            'Unallocated',
          ],
          exportRow: (row) => [
            row.mode,
            '${row.receiptCount}',
            row.totalCollected.toStringAsFixed(2),
            row.totalAllocated.toStringAsFixed(2),
            row.totalUnallocated.toStringAsFixed(2),
          ],
          itemBuilder: (context, row) {
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
                          flex: 4,
                          child: Text(
                            row.mode,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${row.receiptCount}',
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
                          flex: 4,
                          child: Text(
                            '$cs${row.totalCollected.toStringAsFixed(2)}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.successEmerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Allocated: $cs${row.totalAllocated.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                        Text(
                          'Unallocated: $cs${row.totalUnallocated.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.warningAmber,
                          ),
                        ),
                      ],
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
