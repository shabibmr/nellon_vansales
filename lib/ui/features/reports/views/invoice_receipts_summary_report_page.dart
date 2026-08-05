import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/invoice_receipts_summary_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen invoice receipts summary, grouped by payment mode.
///
/// Fetches customer payment receipts via [ReportRepository] and
/// aggregates them by payment mode using [InvoiceReceiptsSummaryAggregator],
/// showing receipt count, total collected, total applied to invoices,
/// and total left unallocated (customer credit).
class InvoiceReceiptsSummaryReportPage extends StatelessWidget {
  const InvoiceReceiptsSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sl = GetIt.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<ReceiptVoucher>(
      create: (_) => ReportBloc<ReceiptVoucher>(
        fetchRemote: () => sl<ReportRepository>().fetchReceipts(),
        initialSortField: InvoiceReceiptsSummarySortField.collected,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = InvoiceReceiptsSummaryAggregator.aggregate(
          receipts: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField:
              state.sortField as InvoiceReceiptsSummarySortField? ??
              InvoiceReceiptsSummarySortField.collected,
          sortAscending: state.sortAscending,
        );
        final totalCount = rows.fold(0, (sum, r) => sum + r.receiptCount);
        final totalCollected = rows.fold(
          0.0,
          (sum, r) => sum + r.totalCollected,
        );

        return SortableReportScaffold<
          InvoiceReceiptsSummaryRow,
          InvoiceReceiptsSummarySortField
        >(
          title: 'Invoice Receipts Summary',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<ReceiptVoucher>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField:
              state.sortField as InvoiceReceiptsSummarySortField? ??
              InvoiceReceiptsSummarySortField.collected,
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
              field: InvoiceReceiptsSummarySortField.mode,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'COUNT',
              flex: 2,
              field: InvoiceReceiptsSummarySortField.count,
            ),
            ReportColumn(
              label: 'COLLECTED',
              flex: 4,
              field: InvoiceReceiptsSummarySortField.collected,
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
