import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/customer_model.dart';
import '../../../../data/models/open_invoice_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';

/// Aging bucket boundaries (in days outstanding since invoice date).
enum _Bucket { d0_15, d15_30, d30_60, d60plus }

extension _BucketLabel on _Bucket {
  String get label {
    switch (this) {
      case _Bucket.d0_15:
        return '0-15';
      case _Bucket.d15_30:
        return '15-30';
      case _Bucket.d30_60:
        return '30-60';
      case _Bucket.d60plus:
        return '>60';
    }
  }

  Color get color {
    switch (this) {
      case _Bucket.d0_15:
        return AppTheme.successEmerald;
      case _Bucket.d15_30:
        return AppTheme.infoSky;
      case _Bucket.d30_60:
        return AppTheme.warningAmber;
      case _Bucket.d60plus:
        return AppTheme.errorRose;
    }
  }
}

/// Per-customer aggregation of outstanding balances split into aging buckets.
class _AgingRow {
  final String customerId;
  final String customerName;
  final Map<_Bucket, double> buckets = {
    _Bucket.d0_15: 0.0,
    _Bucket.d15_30: 0.0,
    _Bucket.d30_60: 0.0,
    _Bucket.d60plus: 0.0,
  };

  _AgingRow({required this.customerId, required this.customerName});

  double amount(_Bucket b) => buckets[b] ?? 0.0;

  double get total => buckets.values.fold(0.0, (sum, v) => sum + v);
}

enum _SortField { name, total }

/// Typed payload for the aging report to fetch both invoices and customer names.
class AgingReportData {
  final List<OpenInvoice> invoices;
  final Map<String, String> customerNames;

  const AgingReportData({
    required this.invoices,
    required this.customerNames,
  });
}

/// Agewise Customer Receivables (AR Aging) report.
///
/// Splits each customer's outstanding invoice balances into 0-15, 15-30, 30-60
/// and >60 day buckets based on the number of days elapsed since the invoice
/// date, computed as of today. Fetches open invoices and customer names live
/// from Zoho Books; the cached Hive snapshot is painted instantly on open
/// while the live fetch is in flight, and kept on screen if that fetch fails.
class AgingReceivablesReportPage extends StatelessWidget {
  const AgingReceivablesReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportBloc<AgingReportData>>(
      create: (_) => ReportBloc<AgingReportData>(
        getLocal: () {
          final invoices = sl<HiveDatabaseService>().getOpenInvoices();
          final customerNames = {
            for (final Customer c in sl<HiveDatabaseService>().getCustomers()) c.id: c.name,
          };
          return [AgingReportData(invoices: invoices, customerNames: customerNames)];
        },
        fetchRemote: () async {
          final rawInvoices = await sl<ZohoApiClient>().fetchOpenInvoices();
          final rawCustomers = await sl<ZohoApiClient>().fetchCustomers();
          final invoices = rawInvoices
              .map((json) => OpenInvoiceModel.fromJson(json))
              .toList();
          final customerNames = {
            for (final customer in rawCustomers.map(CustomerModel.fromJson))
              customer.id: customer.name,
          };
          return [AgingReportData(invoices: invoices, customerNames: customerNames)];
        },
        initialSortField: _SortField.total,
        initialSortAscending: false,
      ),
      child: const _AgingReceivablesReportView(),
    );
  }
}

class _AgingReceivablesReportView extends StatefulWidget {
  const _AgingReceivablesReportView();

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

  /// Buckets every outstanding invoice by age and aggregates per customer.
  List<_AgingRow> _buildReport(ReportState<AgingReportData> state) {
    if (state.rows.isEmpty) return [];
    final data = state.rows.first;
    final openInvoices = data.invoices;
    final customerNames = data.customerNames;

    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final map = <String, _AgingRow>{};

    for (final inv in openInvoices) {
      if (inv.balance <= 0) continue;

      final invDay = DateTime(inv.date.year, inv.date.month, inv.date.day);
      final days = todayDay.difference(invDay).inDays;

      final _Bucket bucket;
      if (days <= 15) {
        bucket = _Bucket.d0_15;
      } else if (days <= 30) {
        bucket = _Bucket.d15_30;
      } else if (days <= 60) {
        bucket = _Bucket.d30_60;
      } else {
        bucket = _Bucket.d60plus;
      }

      final row = map.putIfAbsent(
        inv.customerId,
        () => _AgingRow(
          customerId: inv.customerId,
          customerName: customerNames[inv.customerId] ?? inv.customerId,
        ),
      );
      row.buckets[bucket] = row.amount(bucket) + inv.balance;
    }

    final rows = map.values.toList();
    final sortField = state.sortField as _SortField? ?? _SortField.total;
    final sortAscending = state.sortAscending;

    rows.sort((a, b) {
      int cmp;
      switch (sortField) {
        case _SortField.name:
          cmp = a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          );
          break;
        case _SortField.total:
          cmp = a.total.compareTo(b.total);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  List<_AgingRow> _filterRows(List<_AgingRow> rows) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (r) =>
              r.customerName.toLowerCase().contains(q) ||
              r.customerId.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final DateFormat dateFmt = DateFormat('dd MMM yyyy');

    return BlocListener<ReportBloc<AgingReportData>, ReportState<AgingReportData>>(
      listenWhen: (prev, curr) => curr.error != null && prev.error != curr.error,
      listener: (context, state) {
        showErrorSnackBar(context, 'Could not load report from Zoho: ${state.error}');
      },
      child: BlocBuilder<ReportBloc<AgingReportData>, ReportState<AgingReportData>>(
        builder: (context, state) {
          final allRows = _buildReport(state);
          final rows = _filterRows(allRows);
          final hasQuery = _query.trim().isNotEmpty;

          final bucketTotals = {
            for (final b in _Bucket.values)
              b: rows.fold(0.0, (sum, r) => sum + r.amount(b)),
          };
          final grandTotal = rows.fold(0.0, (sum, r) => sum + r.total);

          return SortableReportScaffold<_AgingRow, _SortField>(
            title: 'Agewise Receivables',
            isLoading: state.isLoading,
            onRefresh: () => context
                .read<ReportBloc<AgingReportData>>()
                .add(const RefreshReport()),
            rows: rows,
            sortField: state.sortField as _SortField? ?? _SortField.total,
            sortAscending: state.sortAscending,
            onSort: (field) {
              final bloc = context.read<ReportBloc<AgingReportData>>();
              if (bloc.state.sortField == field) {
                bloc.add(SetSort(field));
              } else {
                bloc.add(SetSort(field, ascending: field == _SortField.name));
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
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search customers by name…',
                    isDense: true,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppTheme.primaryIndigo,
                    ),
                    suffixIcon: hasQuery
                        ? IconButton(
                            tooltip: 'Clear search',
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
              for (final b in _Bucket.values)
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
                field: _SortField.name,
                alignEnd: false,
              ),
              ReportColumn(label: 'TOTAL DUE', flex: 3, field: _SortField.total),
            ],
            exportHeaders: [
              'Customer',
              for (final b in _Bucket.values) '${b.label} days',
              'Total Due',
            ],
            exportRow: (row) => [
              row.customerName,
              for (final b in _Bucket.values) row.amount(b).toStringAsFixed(2),
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
                          for (final b in _Bucket.values) ...[
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
                            if (b != _Bucket.values.last)
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
        },
      ),
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
