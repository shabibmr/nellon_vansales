import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/sales_return_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aggregated row for a single item across all filtered sales returns.
class _ItemReturnRow {
  final String itemId;
  final String itemName;
  final String sku;
  int totalQty = 0;
  double totalRefunded = 0.0;

  _ItemReturnRow({
    required this.itemId,
    required this.itemName,
    required this.sku,
  });
}

enum _SortField { name, qty, amount }

/// Full-screen itemwise sales-returns summary.
///
/// Fetches every sales return (credit note, with line items) live from
/// Zoho Books and aggregates them by item, showing quantity returned and
/// total refunded. Supports date-range filtering and column sorting.
class ItemwiseReturnsSummaryReportPage extends StatelessWidget {
  const ItemwiseReturnsSummaryReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<SalesReturn>>(
      create: (_) => ReportBloc<SalesReturn>(
        getLocal: () => sl<HiveDatabaseService>().getLocalReturns(),
        fetchRemote: () async {
          final raw = await sl<ZohoApiClient>().fetchSalesReturns();
          return raw.map((json) => SalesReturnModel.fromJson(json)).toList();
        },
        initialSortField: _SortField.amount,
        initialSortAscending: false,
      ),
      child: const _ItemwiseReturnsSummaryReportView(),
    );
  }
}

class _ItemwiseReturnsSummaryReportView extends StatelessWidget {
  const _ItemwiseReturnsSummaryReportView();

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final bloc = context.read<ReportBloc<SalesReturn>>();
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

  List<_ItemReturnRow> _buildReport(ReportState<SalesReturn> state) {
    final map = <String, _ItemReturnRow>{};

    for (final ret in state.rows) {
      final day = DateTime(ret.date.year, ret.date.month, ret.date.day);
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

      for (final line in ret.items) {
        final item = line.invoiceLineItem.item;
        final row = map.putIfAbsent(
          item.id,
          () => _ItemReturnRow(
            itemId: item.id,
            itemName: item.name,
            sku: item.sku,
          ),
        );
        row.totalQty += line.returnedQuantity;
        row.totalRefunded += line.total;
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
          cmp = a.totalRefunded.compareTo(b.totalRefunded);
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

    return BlocListener<ReportBloc<SalesReturn>, ReportState<SalesReturn>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<SalesReturn>, ReportState<SalesReturn>>(
        builder: (context, state) {
          final rows = _buildReport(state);
          final totalQty = rows.fold(0, (sum, r) => sum + r.totalQty);
          final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

          return SortableReportScaffold<_ItemReturnRow, _SortField>(
            title: 'Itemwise Returns Summary',
            isLoading: state.isLoading,
            onRefresh: () => context.read<ReportBloc<SalesReturn>>().add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.amount,
            sortAscending: state.sortAscending,
            onSort: (field) => context.read<ReportBloc<SalesReturn>>().add(SetSort(field)),
            startDate: state.startDate,
            endDate: state.endDate,
            onStartDateTap: () => _pickDate(context, true),
            onEndDateTap: () => _pickDate(context, false),
            onClearDate: () => context.read<ReportBloc<SalesReturn>>().add(const SetDateRange(null, null)),
            emptyIcon: Icons.assignment_return_outlined,
            emptyTitle: 'No return data',
            emptyMessage: 'No sales returns recorded yet.',
            summaryChips: [
              ReportSummaryChip(
                label: 'Items',
                value: '${rows.length}',
                color: AppTheme.infoSky,
              ),
              ReportSummaryChip(
                label: 'Units Returned',
                value: '$totalQty',
                color: AppTheme.warningAmber,
              ),
              ReportSummaryChip(
                label: 'Total Refunded',
                value: '$cs${totalRefunded.toStringAsFixed(2)}',
                color: AppTheme.errorRose,
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
              ReportColumn(label: 'REFUNDED', flex: 3, field: _SortField.amount),
            ],
            exportHeaders: const ['Item', 'SKU', 'Qty', 'Refunded'],
            exportRow: (row) => [
              row.itemName,
              row.sku,
              '${row.totalQty}',
              row.totalRefunded.toStringAsFixed(2),
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
                          '$cs${row.totalRefunded.toStringAsFixed(2)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.errorRose,
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
