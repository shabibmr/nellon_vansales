import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/repositories/report_repository.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/sales_summary_by_customer_item_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Full-screen sales-by-customer (by item) breakdown.
///
/// Fetches sales invoices via [ReportRepository] and aggregates them by
/// customer + item pair using [SalesSummaryByCustomerItemAggregator], showing quantity
/// and amount for each item a customer has bought. Supports date-range filtering and
/// column sorting.
class SalesSummaryByCustomerItemReportPage extends StatelessWidget {
  const SalesSummaryByCustomerItemReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sl = GetIt.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return ReportBlocHost<SalesInvoice>(
      create: (_) => ReportBloc<SalesInvoice>(
        fetchRemote: () => sl<ReportRepository>().fetchInvoices(),
        initialSortField: SalesSummaryByCustomerItemSortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = SalesSummaryByCustomerItemAggregator.aggregate(
          invoices: state.rows,
          startDate: state.startDate,
          endDate: state.endDate,
          sortField:
              state.sortField as SalesSummaryByCustomerItemSortField? ??
              SalesSummaryByCustomerItemSortField.amount,
          sortAscending: state.sortAscending,
        );
        final totalQty = rows.fold(0.0, (sum, r) => sum + r.totalQty);
        final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

        return SortableReportScaffold<
          SalesSummaryByCustomerItemRow,
          SalesSummaryByCustomerItemSortField
        >(
          title: 'Sales by Customer & Item',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<SalesInvoice>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField:
              state.sortField as SalesSummaryByCustomerItemSortField? ??
              SalesSummaryByCustomerItemSortField.amount,
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
          emptyIcon: Icons.shopping_bag_outlined,
          emptyTitle: 'No sales data',
          emptyMessage: 'No invoices recorded yet.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Lines',
              value: '${rows.length}',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Units',
              value: formatQuantity(totalQty),
              color: AppTheme.primaryIndigo,
            ),
            ReportSummaryChip(
              label: 'Total',
              value: '$cs${totalAmount.toStringAsFixed(2)}',
              color: AppTheme.successEmerald,
            ),
          ],
          columns: const [
            ReportColumn(
              label: 'CUSTOMER / ITEM',
              flex: 5,
              field: SalesSummaryByCustomerItemSortField.customer,
              alignEnd: false,
            ),
            ReportColumn(
              label: 'QTY',
              flex: 2,
              field: SalesSummaryByCustomerItemSortField.qty,
            ),
            ReportColumn(
              label: 'AMOUNT',
              flex: 3,
              field: SalesSummaryByCustomerItemSortField.amount,
            ),
          ],
          exportHeaders: const ['Customer', 'Item', 'Qty', 'Amount'],
          exportRow: (row) => [
            row.customerName,
            row.itemName,
            formatQuantity(row.totalQty),
            row.totalAmount.toStringAsFixed(2),
          ],
          itemBuilder: (context, row) {
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.itemName,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatQuantity(row.totalQty),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
                          color: AppTheme.primaryIndigo,
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
