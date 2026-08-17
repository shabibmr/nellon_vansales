import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/transactions_summary_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen "Aggregate of All" transactions summary.
///
/// Fetches invoices, receipts, expenses, and sales returns live from Zoho via
/// [ReportRepository] in parallel and rolls each up into one row per transaction
/// type within the selected date range. Delegated to [TransactionsSummaryAggregator].
class TransactionsSummaryReportPage extends StatelessWidget {
  const TransactionsSummaryReportPage({super.key});

  static (IconData, Color) _getRowStyle(String type) {
    switch (type) {
      case 'Invoices':
        return (Icons.receipt_long_rounded, AppTheme.primaryIndigo);
      case 'Receipts':
        return (Icons.account_balance_wallet_rounded, AppTheme.successEmerald);
      case 'Expenses':
        return (Icons.local_gas_station_rounded, AppTheme.errorRose);
      case 'Sales Returns':
      default:
        return (Icons.assignment_return_rounded, AppTheme.warningAmber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<TransactionsReportData>(
      create: (_) => ReportBloc<TransactionsReportData>(
        fetchRemote: () async {
          final repo = context.read<ReportRepository>();
          final results = await Future.wait([
            repo.fetchInvoices(),
            repo.fetchReceipts(),
            repo.fetchExpenses(),
            repo.fetchSalesReturns(),
          ]);

          return [
            TransactionsReportData(
              invoices: results[0] as List<SalesInvoice>,
              receipts: results[1] as List<ReceiptVoucher>,
              expenses: results[2] as List<ExpenseEntry>,
              returns: results[3] as List<SalesReturn>,
            ),
          ];
        },
        initialSortField: TransactionsSummarySortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final data = state.rows.isNotEmpty
            ? state.rows.first
            : const TransactionsReportData(
                invoices: [],
                receipts: [],
                expenses: [],
                returns: [],
              );

        final sortField =
            state.sortField as TransactionsSummarySortField? ??
            TransactionsSummarySortField.amount;

        final rows = TransactionsSummaryAggregator.aggregate(
          data: data,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField: sortField,
          sortAscending: state.sortAscending,
        );

        final totalCount = rows.fold(0, (sum, r) => sum + r.count);
        final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

        return SortableReportScaffold<
          TransactionsSummaryRow,
          TransactionsSummarySortField
        >(
          title: 'Transactions Summary',
          isLoading: state.isLoading,
          onRefresh: () => context
              .read<ReportBloc<TransactionsReportData>>()
              .add(const RefreshReport()),
          rows: rows,
          sortField: sortField,
          sortAscending: state.sortAscending,
          onSort: (field) => context
              .read<ReportBloc<TransactionsReportData>>()
              .add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () =>
              pickReportDate<TransactionsReportData>(context, true),
          onEndDateTap: () =>
              pickReportDate<TransactionsReportData>(context, false),
          onClearDate: () => context
              .read<ReportBloc<TransactionsReportData>>()
              .add(const SetDateRange(null, null)),
          emptyIcon: Icons.receipt_long_outlined,
          emptyTitle: 'No transactions',
          emptyMessage: 'No transactions recorded yet.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Transactions',
              value: '$totalCount',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Total Value',
              value: '$cs${totalAmount.toStringAsFixed(2)}',
              color: AppTheme.primaryIndigo,
            ),
          ],
          columns: const [
            ReportColumn(
              label: 'TYPE',
              flex: 5,
              field: TransactionsSummarySortField.type,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'COUNT',
              flex: 2,
              field: TransactionsSummarySortField.count,
            ),
            ReportColumn(
              label: 'AMOUNT',
              flex: 3,
              field: TransactionsSummarySortField.amount,
            ),
          ],
          exportHeaders: const ['Type', 'Count', 'Amount'],
          exportRow: (row) => [
            row.type,
            '${row.count}',
            row.totalAmount.toStringAsFixed(2),
          ],
          itemBuilder: (context, row) {
            final (icon, color) = _getRowStyle(row.type);
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Text(
                        row.type,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${row.count}',
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color,
                        ),
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
