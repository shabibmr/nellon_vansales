import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/date_filter.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../widgets/report_bloc_host.dart';
import '../widgets/report_date_actions.dart';

/// Aggregated row for a single item across all filtered invoices.
class _ItemSalesRow {
  final String itemId;
  final String itemName;
  final String sku;
  double totalQty = 0;
  double totalAmount = 0.0;
  final Set<String> customerIds;

  _ItemSalesRow({
    required this.itemId,
    required this.itemName,
    required this.sku,
  }) : customerIds = {};

  int get customerCount => customerIds.length;
}

enum _SortField { name, qty, amount, customers }

/// Full-screen itemwise sales report page.
///
/// Fetches every invoice (with line items) live from Zoho Books and
/// aggregates them by item, showing total quantity sold, total amount, and
/// number of customers per item. Supports date-range filtering and column
/// sorting. The local invoice cache is painted instantly on open while the
/// live fetch is in flight.
class ItemSalesReportPage extends StatelessWidget {
  const ItemSalesReportPage({super.key});

  List<_ItemSalesRow> _buildReport(ReportState<SalesInvoice> state) {
    final map = <String, _ItemSalesRow>{};

    final filtered = filterByDateRange(
      state.rows,
      (inv) => inv.date,
      startDate: state.startDate,
      endDate: state.endDate,
    );
    for (final inv in filtered) {
      for (final line in inv.items) {
        final row = map.putIfAbsent(
          line.item.id,
          () => _ItemSalesRow(
            itemId: line.item.id,
            itemName: line.item.name,
            sku: line.item.sku,
          ),
        );
        row.totalQty += line.quantityInBase;
        row.totalAmount += line.total;
        row.customerIds.add(inv.customerId);
      }
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.amount;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.name:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case _SortField.qty:
          cmp = a.totalQty.compareTo(b.totalQty);
          break;
        case _SortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
        case _SortField.customers:
          cmp = a.customerCount.compareTo(b.customerCount);
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
          final list = raw.map((json) => SalesInvoiceModel.fromJson(json)).toList();
          final salesperson = sl<HiveDatabaseService>().getCurrentSalesperson();
          final locationId = salesperson?.locationId;
          if (locationId != null && locationId.isNotEmpty) {
            return list.where((inv) => inv.locationId == locationId).toList();
          }
          return list;
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      builder: (context, state) {
        final rows = _buildReport(state);
        final totalQty = rows.fold(0.0, (sum, r) => sum + r.totalQty);
        final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

        return SortableReportScaffold<_ItemSalesRow, _SortField>(
          title: 'Item Sales Report',
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
          emptyIcon: Icons.bar_chart_rounded,
          emptyTitle: 'No sales data',
          emptyMessage: 'No invoices recorded yet.',
          emptyFilteredMessage: 'No invoices in the selected date range.',
          summaryChips: [
            ReportSummaryChip(
              label: 'Items',
              value: '${rows.length}',
              color: AppTheme.infoSky,
            ),
            ReportSummaryChip(
              label: 'Units Sold',
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
              label: 'ITEM',
              flex: 5,
              field: _SortField.name,
              alignEnd: false,
            ),
            ReportColumn(label: 'QTY', flex: 2, field: _SortField.qty),
            ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
            ReportColumn(label: 'CUST', flex: 2, field: _SortField.customers),
          ],
          exportHeaders: const ['Item', 'SKU', 'Qty', 'Amount', 'Customers'],
          exportRow: (row) => [
            row.itemName,
            row.sku,
            formatQuantity(row.totalQty),
            row.totalAmount.toStringAsFixed(2),
            '${row.customerCount}',
          ],
          itemBuilder: (context, row) {
            final pct = totalAmount > 0 ? (row.totalAmount / totalAmount) : 0.0;

            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.itemName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'SKU: ${row.sku}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
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
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${row.customerCount}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Share-of-total progress bar
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
                    const SizedBox(height: 4),
                    Text(
                      '${(pct * 100).toStringAsFixed(1)}% of total sales',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
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
