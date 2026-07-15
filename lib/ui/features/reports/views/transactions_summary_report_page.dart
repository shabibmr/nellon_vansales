import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/models/sales_return_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aggregated row for a single transaction type across the filtered period.
class _TypeRow {
  final String type;
  final IconData icon;
  final Color color;
  int count = 0;
  double totalAmount = 0.0;

  _TypeRow({required this.type, required this.icon, required this.color});
}

enum _SortField { type, count, amount }

/// Typed payload for the transactions summary report.
class TransactionsReportData {
  final List<SalesInvoice> invoices;
  final List<ReceiptVoucher> receipts;
  final List<ExpenseEntry> expenses;
  final List<SalesReturn> returns;

  const TransactionsReportData({
    required this.invoices,
    required this.receipts,
    required this.expenses,
    required this.returns,
  });
}

/// Full-screen "Aggregate of All" transactions summary.
///
/// Fetches invoices, receipts, expenses, and sales returns live from Zoho in
/// parallel and rolls each up into one row per transaction type within the
/// selected date range. The local cache is painted instantly on open while
/// the live fetch is in flight.
class TransactionsSummaryReportPage extends StatelessWidget {
  const TransactionsSummaryReportPage({super.key});

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
    return BlocProvider<ReportBloc<TransactionsReportData>>(
      create: (_) => ReportBloc<TransactionsReportData>(
        getLocal: () {
          final invoices = sl<HiveDatabaseService>().getLocalInvoices();
          final receipts = sl<HiveDatabaseService>().getLocalReceipts();
          final expenses = sl<HiveDatabaseService>().getLocalExpenses();
          final returns = sl<HiveDatabaseService>().getLocalReturns();
          return [
            TransactionsReportData(
              invoices: invoices,
              receipts: receipts,
              expenses: expenses,
              returns: returns,
            )
          ];
        },
        fetchRemote: () async {
          final results = await Future.wait([
            sl<ZohoApiClient>().fetchInvoices(),
            sl<ZohoApiClient>().fetchReceipts(),
            sl<ZohoApiClient>().fetchExpenses(),
            sl<ZohoApiClient>().fetchSalesReturns(),
          ]);
          final invoices = (results[0])
              .map((j) => SalesInvoiceModel.fromJson(j))
              .toList();
          final receipts = (results[1])
              .map((j) => ReceiptVoucherModel.fromJson(j))
              .toList();
          final expenses = (results[2])
              .map((j) => ExpenseEntryModel.fromJson(_normalizeExpenseJson(j)))
              .toList();
          final returns = (results[3])
              .map((j) => SalesReturnModel.fromJson(j))
              .toList();
          return [
            TransactionsReportData(
              invoices: invoices,
              receipts: receipts,
              expenses: expenses,
              returns: returns,
            )
          ];
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      child: const _TransactionsSummaryReportView(),
    );
  }
}

class _TransactionsSummaryReportView extends StatelessWidget {
  const _TransactionsSummaryReportView();

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final bloc = context.read<ReportBloc<TransactionsReportData>>();
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

  bool _inRange(DateTime date, DateTime? startDate, DateTime? endDate) {
    final day = DateTime(date.year, date.month, date.day);
    if (startDate != null) {
      final s = DateTime(startDate.year, startDate.month, startDate.day);
      if (day.isBefore(s)) return false;
    }
    if (endDate != null) {
      final e = DateTime(endDate.year, endDate.month, endDate.day);
      if (day.isAfter(e)) return false;
    }
    return true;
  }

  List<_TypeRow> _buildReport(ReportState<TransactionsReportData> state) {
    if (state.rows.isEmpty) return [];
    final data = state.rows.first;

    final invoiceRow = _TypeRow(
      type: 'Invoices',
      icon: Icons.receipt_long_rounded,
      color: AppTheme.primaryIndigo,
    );
    final receiptRow = _TypeRow(
      type: 'Receipts',
      icon: Icons.account_balance_wallet_rounded,
      color: AppTheme.successEmerald,
    );
    final expenseRow = _TypeRow(
      type: 'Expenses',
      icon: Icons.local_gas_station_rounded,
      color: AppTheme.errorRose,
    );
    final returnRow = _TypeRow(
      type: 'Sales Returns',
      icon: Icons.assignment_return_rounded,
      color: AppTheme.warningAmber,
    );

    for (final inv in data.invoices) {
      if (!_inRange(inv.date, state.startDate, state.endDate)) continue;
      invoiceRow.count++;
      invoiceRow.totalAmount += inv.total;
    }
    for (final rcpt in data.receipts) {
      if (!_inRange(rcpt.date, state.startDate, state.endDate)) continue;
      receiptRow.count++;
      receiptRow.totalAmount += rcpt.amount;
    }
    for (final exp in data.expenses) {
      if (!_inRange(exp.date, state.startDate, state.endDate)) continue;
      expenseRow.count++;
      expenseRow.totalAmount += exp.amount;
    }
    for (final ret in data.returns) {
      if (!_inRange(ret.date, state.startDate, state.endDate)) continue;
      returnRow.count++;
      returnRow.totalAmount += ret.total;
    }

    final rows = [invoiceRow, receiptRow, expenseRow, returnRow];
    final sortField = state.sortField as _SortField? ?? _SortField.amount;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.type:
          cmp = a.type.compareTo(b.type);
          break;
        case _SortField.count:
          cmp = a.count.compareTo(b.count);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return BlocListener<ReportBloc<TransactionsReportData>, ReportState<TransactionsReportData>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<TransactionsReportData>, ReportState<TransactionsReportData>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalCount = rows.fold(0, (sum, r) => sum + r.count);
          final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

          return SortableReportScaffold<_TypeRow, _SortField>(
            title: 'Transactions Summary',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<TransactionsReportData>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.amount,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<TransactionsReportData>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<TransactionsReportData>>().add(const SetDateRange(null, null)),
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
                field: _SortField.type,
                alignEnd: false,
              ),
              ReportColumn(label: 'COUNT', flex: 2, field: _SortField.count),
              ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
            ],
            exportHeaders: const ['Type', 'Count', 'Amount'],
            exportRow: (row) => [
              row.type,
              '${row.count}',
              row.totalAmount.toStringAsFixed(2),
            ],
            itemBuilder: (context, row) {
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: row.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(row.icon, color: row.color, size: 18),
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
                            color: row.color,
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
      ),
    );
  }
}
