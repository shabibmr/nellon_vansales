import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aggregated row for a single customer across the filtered invoices.
class _CustomerRow {
  final String customerId;
  final String customerName;
  int invoiceCount = 0;
  double totalValue = 0.0;

  _CustomerRow({required this.customerId, required this.customerName});
}

enum _SortField { name, count, value }

/// Full-screen sales-by-customer (value) summary.
///
/// Fetches every invoice live from Zoho Books and aggregates them by
/// customer, showing invoice count and total value per customer. Supports
/// date-range filtering and column sorting.
class SalesSummaryByCustomerValueReportPage extends StatelessWidget {
  const SalesSummaryByCustomerValueReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<SalesInvoice>>(
      create: (_) => ReportBloc<SalesInvoice>(
        getLocal: () => sl<HiveDatabaseService>().getLocalInvoices(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchInvoices();
          return raw.map((json) => SalesInvoiceModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.value,
        initialSortAscending: false,
      ),
      child: const _SalesSummaryByCustomerValueReportView(),
    );
  }
}

class _SalesSummaryByCustomerValueReportView extends StatelessWidget {
  const _SalesSummaryByCustomerValueReportView();

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final bloc = context.read<ReportBloc<SalesInvoice>>();
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

  List<_CustomerRow> _buildReport(ReportState<SalesInvoice> state) {
    final map = <String, _CustomerRow>{};

    for (final inv in state.rows) {
      final day = DateTime(inv.date.year, inv.date.month, inv.date.day);
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
        inv.customerId,
        () => _CustomerRow(
          customerId: inv.customerId,
          customerName: inv.customerName,
        ),
      );
      row.invoiceCount++;
      row.totalValue += inv.total;
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.value;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.count:
          cmp = a.invoiceCount.compareTo(b.invoiceCount);
          break;
        case _SortField.value:
          cmp = a.totalValue.compareTo(b.totalValue);
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

    return BlocListener<ReportBloc<SalesInvoice>, ReportState<SalesInvoice>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<SalesInvoice>, ReportState<SalesInvoice>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalInvoices = rows.fold(0, (sum, r) => sum + r.invoiceCount);
          final totalValue = rows.fold(0.0, (sum, r) => sum + r.totalValue);

          return SortableReportScaffold<_CustomerRow, _SortField>(
            title: 'Sales Summary by Customer',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesInvoice>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.value,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesInvoice>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<SalesInvoice>>().add(const SetDateRange(null, null)),
            emptyIcon: Icons.people_outline_rounded,
            emptyTitle: 'No sales data',
            emptyMessage: 'No invoices recorded yet.',
            summaryChips: [
              ReportSummaryChip(
                label: 'Customers',
                value: '${rows.length}',
                color: AppTheme.infoSky,
              ),
              ReportSummaryChip(
                label: 'Invoices',
                value: '$totalInvoices',
                color: AppTheme.primaryIndigo,
              ),
              ReportSummaryChip(
                label: 'Total',
                value: '$cs${totalValue.toStringAsFixed(2)}',
                color: AppTheme.successEmerald,
              ),
            ],
            columns: const [
              ReportColumn(
                label: 'CUSTOMER',
                flex: 5,
                field: _SortField.name,
                alignEnd: false,
              ),
              ReportColumn(label: 'INVOICES', flex: 2, field: _SortField.count),
              ReportColumn(label: 'VALUE', flex: 3, field: _SortField.value),
            ],
            exportHeaders: const ['Customer', 'Invoices', 'Value'],
            exportRow: (row) => [
              row.customerName,
              '${row.invoiceCount}',
              row.totalValue.toStringAsFixed(2),
            ],
            itemBuilder: (context, row) {
              final pct = totalValue > 0 ? (row.totalValue / totalValue) : 0.0;

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
                              '${row.invoiceCount}',
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
                              '$cs${row.totalValue.toStringAsFixed(2)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.primaryIndigo,
                              ),
                              overflow: TextOverflow.ellipsis,
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
                          color: AppTheme.primaryIndigo,
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
