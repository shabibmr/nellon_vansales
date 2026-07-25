import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_filter.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Aggregated row for a single (customer, item) pair across the filtered
/// invoices.
class _CustomerItemRow {
  final String customerId;
  final String customerName;
  final String itemId;
  final String itemName;
  double totalQty = 0;
  double totalAmount = 0.0;

  _CustomerItemRow({
    required this.customerId,
    required this.customerName,
    required this.itemId,
    required this.itemName,
  });
}

enum _SortField { customer, item, qty, amount }

/// Full-screen sales-by-customer (by item) breakdown.
///
/// Fetches every invoice (with line items) live from Zoho Books and
/// aggregates them by customer + item pair, showing quantity and amount for
/// each item a customer has bought. Supports date-range filtering and
/// column sorting.
class SalesSummaryByCustomerItemReportPage extends StatelessWidget {
  const SalesSummaryByCustomerItemReportPage({super.key});

  List<_CustomerItemRow> _buildReport(ReportState<SalesInvoice> state) {
    final map = <String, _CustomerItemRow>{};

    final filtered = filterByDateRange(
      state.rows,
      (inv) => inv.date,
      startDate: state.startDate,
      endDate: state.endDate,
    );
    for (final inv in filtered) {
      for (final line in inv.items) {
        final key = '${inv.customerId}::${line.item.id}';
        final row = map.putIfAbsent(
          key,
          () => _CustomerItemRow(
            customerId: inv.customerId,
            customerName: inv.customerName,
            itemId: line.item.id,
            itemName: line.item.name,
          ),
        );
        row.totalQty += line.quantityInBase;
        row.totalAmount += line.total;
      }
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.amount;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.customer:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.item:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case _SortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
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

    return ReportBlocHost<SalesInvoice>(
      create: (_) => ReportBloc<SalesInvoice>(
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchInvoices();
          return raw.map((json) => SalesInvoiceModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = _buildReport(state);
        final totalQty = rows.fold(0.0, (sum, r) => sum + r.totalQty);
        final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

        return SortableReportScaffold<_CustomerItemRow, _SortField>(
          title: 'Sales by Customer & Item',
          isLoading: state.isLoading,
          onRefresh: () => context.read<ReportBloc<SalesInvoice>>().add(
            const RefreshReport(),
          ),
          rows: rows,
          sortField: state.sortField as _SortField? ?? _SortField.amount,
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
              field: _SortField.customer,
              alignEnd: false,
            ),
            ReportColumn(label: 'QTY', flex: 2, field: _SortField.qty),
            ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
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
