import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/sales_summary_by_customer_value_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen sales-by-customer (value) summary.
///
/// Fetches sales invoices via [ReportRepository] and aggregates them by
/// customer using [SalesSummaryByCustomerValueAggregator], showing invoice count
/// and total value per customer. Supports date-range filtering and column sorting.
class SalesSummaryByCustomerValueReportPage extends StatelessWidget {
  const SalesSummaryByCustomerValueReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sl = GetIt.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesInvoice>(
      create: (_) => ReportBloc<SalesInvoice>(
        fetchRemote: () => sl<ReportRepository>().fetchInvoices(),
        initialSortField: SalesSummaryByCustomerValueSortField.value,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = SalesSummaryByCustomerValueAggregator.aggregate(
          invoices: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField:
              state.sortField as SalesSummaryByCustomerValueSortField? ??
              SalesSummaryByCustomerValueSortField.value,
          sortAscending: state.sortAscending,
        );
        final totalInvoices = rows.fold(0, (sum, r) => sum + r.invoiceCount);
        final totalValue = rows.fold(0.0, (sum, r) => sum + r.totalValue);

        return SortableReportScaffold<
          SalesSummaryByCustomerValueRow,
          SalesSummaryByCustomerValueSortField
        >(
          title: 'Sales Summary by Customer',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<SalesInvoice>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField:
              state.sortField as SalesSummaryByCustomerValueSortField? ??
              SalesSummaryByCustomerValueSortField.value,
          sortAscending: state.sortAscending,
          onSort: (field) =>
              context.read<ReportBloc<SalesInvoice>>().add(SetSort(field)),
          startDate: state.startDate,
          endDate: state.endDate,
          onStartDateTap: () => pickReportDate<SalesInvoice>(context, true),
          onEndDateTap: () => pickReportDate<SalesInvoice>(context, false),
          onClearDate: () => context.read<ReportBloc<SalesInvoice>>().add(
            const SetDateRange(null, null),
          ),
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
              field: SalesSummaryByCustomerValueSortField.name,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'INVOICES',
              flex: 2,
              field: SalesSummaryByCustomerValueSortField.count,
            ),
            ReportColumn(
              label: 'VALUE',
              flex: 3,
              field: SalesSummaryByCustomerValueSortField.value,
            ),
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
    );
  }
}
