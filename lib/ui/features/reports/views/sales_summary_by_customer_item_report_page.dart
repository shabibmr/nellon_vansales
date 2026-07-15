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

/// Aggregated row for a single (customer, item) pair across the filtered
/// invoices.
class _CustomerItemRow {
  final String customerId;
  final String customerName;
  final String itemId;
  final String itemName;
  int totalQty = 0;
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

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<SalesInvoice>>(
      create: (_) => ReportBloc<SalesInvoice>(
        getLocal: () => sl<HiveDatabaseService>().getLocalInvoices(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchInvoices();
          return raw.map((json) => SalesInvoiceModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      child: const _SalesSummaryByCustomerItemReportView(),
    );
  }
}

class _SalesSummaryByCustomerItemReportView extends StatelessWidget {
  const _SalesSummaryByCustomerItemReportView();

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

  List<_CustomerItemRow> _buildReport(ReportState<SalesInvoice> state) {
    final map = <String, _CustomerItemRow>{};

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
        row.totalQty += line.quantity;
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

    return BlocListener<ReportBloc<SalesInvoice>, ReportState<SalesInvoice>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<SalesInvoice>, ReportState<SalesInvoice>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalQty = rows.fold(0, (sum, r) => sum + r.totalQty);
          final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

          return SortableReportScaffold<_CustomerItemRow, _SortField>(
            title: 'Sales by Customer & Item',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesInvoice>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.amount,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesInvoice>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<SalesInvoice>>().add(const SetDateRange(null, null)),
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
                value: '$totalQty',
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
              '${row.totalQty}',
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
                          '${row.totalQty}',
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
      ),
    );
  }
}
