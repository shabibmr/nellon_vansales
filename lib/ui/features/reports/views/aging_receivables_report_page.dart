import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/open_invoice.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/utils/snackbars.dart';

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

/// Agewise Customer Receivables (AR Aging) report.
///
/// Splits each customer's outstanding invoice balances into 0-15, 15-30, 30-60
/// and >60 day buckets based on the number of days elapsed since the invoice
/// date, computed as of today. Data is sourced from the cached open invoices
/// snapshot ([HiveDatabaseService.getOpenInvoices]).
class AgingReceivablesReportPage extends StatefulWidget {
  const AgingReceivablesReportPage({super.key});

  @override
  State<AgingReceivablesReportPage> createState() => _AgingReceivablesReportPageState();
}

class _AgingReceivablesReportPageState extends State<AgingReceivablesReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final SyncRepository _syncRepository = sl<SyncRepository>();
  final DateFormat _dateFmt = DateFormat('dd MMM yyyy');

  _SortField _sortField = _SortField.total;
  bool _sortAscending = false;
  bool _isSyncing = false;

  List<OpenInvoice> _openInvoices = [];
  Map<String, String> _customerNames = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Paint the cached snapshot instantly, then pull a fresh copy from Zoho.
    _syncFromZoho();
  }

  /// Reads the local open-invoices + customers snapshot from Hive.
  void _load() {
    _openInvoices = _db.getOpenInvoices();
    _customerNames = {
      for (final Customer c in _db.getCustomers()) c.id: c.name,
    };
  }

  /// Pulls live open invoices (and customer names) from Zoho into the local
  /// cache, then rebuilds. Offline-first: on failure the cached snapshot is
  /// kept and an error is surfaced.
  Future<void> _syncFromZoho() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await _syncRepository.syncMaster(MasterType.customers);
      await _syncRepository.syncMaster(MasterType.openInvoices);
      if (!mounted) return;
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'Could not refresh from Zoho: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Buckets every outstanding invoice by age and aggregates per customer.
  List<_AgingRow> _buildReport() {
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final map = <String, _AgingRow>{};

    for (final inv in _openInvoices) {
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
          customerName: _customerNames[inv.customerId] ?? inv.customerId,
        ),
      );
      row.buckets[bucket] = row.amount(bucket) + inv.balance;
    }

    final rows = map.values.toList();
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.name:
          cmp = a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase());
          break;
        case _SortField.total:
          cmp = a.total.compareTo(b.total);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = field == _SortField.name; // names default A→Z, amounts high→low
      }
    });
  }

  Widget _sortIcon(_SortField field) {
    if (_sortField != field) {
      return const Icon(Icons.unfold_more, size: 14, color: Colors.grey);
    }
    return Icon(
      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: AppTheme.primaryIndigo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final rows = _buildReport();

    final bucketTotals = {
      for (final b in _Bucket.values)
        b: rows.fold(0.0, (sum, r) => sum + r.amount(b)),
    };
    final grandTotal = rows.fold(0.0, (sum, r) => sum + r.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agewise Receivables'),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Sync from Zoho',
              icon: const Icon(Icons.cloud_sync_rounded),
              onPressed: _syncFromZoho,
            ),
        ],
      ),
      body: Column(
        children: [
          // As-of + grand total banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryIndigo.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: AppTheme.primaryIndigo, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Receivable',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                        Text(
                          'As of ${_dateFmt.format(DateTime.now())}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
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
          ),

          // Bucket summary strip
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  for (final b in _Bucket.values) ...[
                    Expanded(
                      child: _BucketChip(
                        label: '${b.label} days',
                        value: '$cs${bucketTotals[b]!.toStringAsFixed(0)}',
                        color: b.color,
                        isDark: isDark,
                      ),
                    ),
                    if (b != _Bucket.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 10),

          // Sort header
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _toggleSort(_SortField.name),
                      child: Row(
                        children: [
                          const Text('CUSTOMER',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 2),
                          _sortIcon(_SortField.name),
                        ],
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _toggleSort(_SortField.total),
                      child: Row(
                        children: [
                          _sortIcon(_SortField.total),
                          const SizedBox(width: 2),
                          const Text('TOTAL DUE',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 4),

          // List body
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 64,
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No outstanding receivables',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sync open invoices from the Masters page to populate this report.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = rows[index];
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
                                    if (b != _Bucket.values.last) const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Compact summary chip for a bucket total in the top strip.
class _BucketChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _BucketChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
              ),
            ),
          ),
        ],
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
              color: active ? color : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
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
                    : (isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
