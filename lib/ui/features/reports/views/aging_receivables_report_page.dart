import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../domain/repositories/report_repository.dart';
import '../../../../domain/repositories/customer_repository.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../core/widgets/customer_selector_sheet.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../aggregators/aging_receivables_aggregator.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../widgets/report_bloc_host.dart';

extension _AgingBucketColor on AgingBucket {
  Color get color {
    switch (this) {
      case AgingBucket.d0_15:
        return AppTheme.successEmerald;
      case AgingBucket.d15_30:
        return AppTheme.infoSky;
      case AgingBucket.d30_60:
        return AppTheme.warningAmber;
      case AgingBucket.d60plus:
        return AppTheme.errorRose;
    }
  }
}

/// Agewise Customer Receivables (AR Aging) report.
///
/// Splits each customer's outstanding invoice balances into 0-15, 15-30, 30-60
/// and >60 day buckets based on the number of days elapsed since the invoice
/// date, computed as of today. Fetches open invoices and customer names via
/// [ReportRepository] and delegates row aggregation and sorting to [AgingReceivablesAggregator].
class AgingReceivablesReportPage extends StatelessWidget {
  const AgingReceivablesReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sl = GetIt.instance;

    return ReportBlocHost<AgingReportData>(
      create: (_) => ReportBloc<AgingReportData>(
        fetchRemote: () async {
          final repository = sl<ReportRepository>();
          final invoices = await repository.fetchOpenInvoices();
          final customers = await repository.fetchCustomers();
          final customerNames = {
            for (final customer in customers) customer.id: customer.name,
          };
          return [
            AgingReportData(
              invoices: invoices,
              customerNames: customerNames,
            ),
          ];
        },
        initialSortField: AgingSortField.total,
        initialSortAscending: false,
      ),
      builder: (context, state) => _AgingReceivablesReportView(state: state),
    );
  }
}

class _AgingReceivablesReportView extends StatefulWidget {
  final ReportState<AgingReportData> state;

  const _AgingReceivablesReportView({required this.state});

  @override
  State<_AgingReceivablesReportView> createState() =>
      _AgingReceivablesReportViewState();
}

class _AgingReceivablesReportViewState
    extends State<_AgingReceivablesReportView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCustomerSelector(BuildContext context) {
    final allCustomers = context.read<CustomerRepository>().getCustomers()
      ..sort((a, b) => a.name.compareTo(b.name));
    CustomerSelectorSheet.show(
      context,
      customers: allCustomers,
      onSelected: (customer) {
        _searchController.text = customer.name;
        setState(() => _query = customer.name);
      },
    );
  }

  List<AgingRow> _buildReport(ReportState<AgingReportData> state) {
    if (state.rows.isEmpty) return [];
    final data = state.rows.first;
    return AgingReceivablesAggregator.aggregate(
      openInvoices: data.invoices,
      customerNames: data.customerNames,
      sortField: state.sortField as AgingSortField? ?? AgingSortField.total,
      sortAscending: state.sortAscending,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final DateFormat dateFmt = DateFormat('dd MMM yyyy');

    final state = widget.state;
    final allRows = _buildReport(state);
    final rows = AgingReceivablesAggregator.filter(allRows, _query);
    final hasQuery = _query.trim().isNotEmpty;

    final bucketTotals = {
      for (final b in AgingBucket.values)
        b: rows.fold(0.0, (sum, r) => sum + r.amount(b)),
    };
    final grandTotal = rows.fold(0.0, (sum, r) => sum + r.total);

    return SortableReportScaffold<AgingRow, AgingSortField>(
      title: 'Agewise Receivables',
      isLoading: state.isLoading,
      onRefresh: () => context.read<ReportBloc<AgingReportData>>().add(
        const RefreshReport(),
      ),
      rows: rows,
      sortField: state.sortField as AgingSortField? ?? AgingSortField.total,
      sortAscending: state.sortAscending,
      onSort: (field) {
        final bloc = context.read<ReportBloc<AgingReportData>>();
        if (bloc.state.sortField == field) {
          bloc.add(SetSort(field));
        } else {
          bloc.add(SetSort(field, ascending: field == AgingSortField.name));
        }
      },
      emptyIcon: Icons.account_balance_wallet_outlined,
      emptyTitle: hasQuery
          ? 'No matching customers'
          : 'No outstanding receivables',
      emptyMessage: hasQuery
          ? 'No customers match "${_query.trim()}".\n'
                'Try a different name.'
          : 'Sync open invoices from the Masters page to populate this report.',
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: AppTheme.primaryIndigo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppTheme.primaryIndigo,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasQuery
                            ? 'Filtered Receivable'
                            : 'Total Receivable',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                      Text(
                        'As of ${dateFmt.format(DateTime.now())}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? const Color(0xFF475569)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$cs${grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            readOnly: true,
            onTap: () => _showCustomerSelector(context),
            decoration: InputDecoration(
              hintText: 'Tap to search customers…',
              isDense: true,
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppTheme.primaryIndigo,
              ),
              suffixIcon: hasQuery
                  ? IconButton(
                      tooltip: 'Clear filter',
                      icon: Icon(
                        Icons.cancel,
                        size: 20,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      summaryChips: [
        for (final b in AgingBucket.values)
          ReportSummaryChip(
            label: '${b.label} days',
            value: '$cs${bucketTotals[b]!.toStringAsFixed(0)}',
            color: b.color,
          ),
      ],
      columns: const [
        ReportColumn(
          label: 'CUSTOMER',
          flex: 5,
          field: AgingSortField.name,
          alignEnd: false,
        ),
        ReportColumn(
          label: 'TOTAL DUE',
          flex: 3,
          field: AgingSortField.total,
        ),
      ],
      exportHeaders: [
        'Customer',
        for (final b in AgingBucket.values) '${b.label} days',
        'Total Due',
      ],
      exportRow: (row) => [
        row.customerName,
        for (final b in AgingBucket.values) row.amount(b).toStringAsFixed(2),
        row.total.toStringAsFixed(2),
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
                      child: Text(
                        row.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$cs${row.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final b in AgingBucket.values) ...[
                      Expanded(
                        child: _BucketCell(
                          label: b.label,
                          value: row.amount(b) > 0
                              ? '$cs${row.amount(b).toStringAsFixed(0)}'
                              : '—',
                          color: b.color,
                          active: row.amount(b) > 0,
                          isDark: isDark,
                        ),
                      ),
                      if (b != AgingBucket.values.last)
                        const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Per-customer bucket cell shown inside each row card.
class _BucketCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool active;
  final bool isDark;

  const _BucketCell({
    required this.label,
    required this.value,
    required this.color,
    required this.active,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.08)
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.25)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active
                  ? color
                  : (isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: active
                    ? (isDark ? AppTheme.darkText : AppTheme.lightText)
                    : (isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFF94A3B8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
