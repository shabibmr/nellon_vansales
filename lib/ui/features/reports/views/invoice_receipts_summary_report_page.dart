import 'package:flutter/material.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';

/// Aggregated row for a single payment mode across the filtered period.
class _ModeRow {
  final String mode;
  int receiptCount = 0;
  double totalCollected = 0.0;
  double totalAllocated = 0.0;
  double totalUnallocated = 0.0;

  _ModeRow({required this.mode});
}

enum _SortField { mode, count, collected }

/// Full-screen invoice receipts summary, grouped by payment mode.
///
/// Fetches every customer payment (receipt) live from Zoho Books and
/// aggregates by payment mode, showing receipt count, total collected,
/// total applied to invoices, and total left unallocated (customer credit).
class InvoiceReceiptsSummaryReportPage extends StatefulWidget {
  const InvoiceReceiptsSummaryReportPage({super.key});

  @override
  State<InvoiceReceiptsSummaryReportPage> createState() =>
      _InvoiceReceiptsSummaryReportPageState();
}

class _InvoiceReceiptsSummaryReportPageState
    extends State<InvoiceReceiptsSummaryReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();

  DateTime? _startDate;
  DateTime? _endDate;
  _SortField _sortField = _SortField.collected;
  bool _sortAscending = false;
  bool _isLoading = false;

  List<ReceiptVoucher> _allReceipts = [];

  @override
  void initState() {
    super.initState();
    _allReceipts = _db.getLocalReceipts();
    _fetchFromZoho();
  }

  Future<void> _fetchFromZoho() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final raw = await _apiClient.fetchReceipts();
      final receipts = raw
          .map((json) => ReceiptVoucherModel.fromJson(json))
          .toList();
      if (!mounted) return;
      setState(() {
        _allReceipts = receipts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorSnackBar(context, 'Could not load report from Zoho: $e');
    }
  }

  List<_ModeRow> _buildReport() {
    final map = <String, _ModeRow>{};

    for (final rcpt in _allReceipts) {
      final day = DateTime(rcpt.date.year, rcpt.date.month, rcpt.date.day);
      if (_startDate != null) {
        final s = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        );
        if (day.isBefore(s)) continue;
      }
      if (_endDate != null) {
        final e = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
        if (day.isAfter(e)) continue;
      }

      final row = map.putIfAbsent(
        rcpt.paymentMode,
        () => _ModeRow(mode: rcpt.paymentMode),
      );
      row.receiptCount++;
      row.totalCollected += rcpt.amount;
      row.totalAllocated += rcpt.totalAllocated;
      row.totalUnallocated += rcpt.unallocatedAmount;
    }

    final rows = map.values.toList();
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.mode:
          cmp = a.mode.compareTo(b.mode);
          break;
        case _SortField.count:
          cmp = a.receiptCount.compareTo(b.receiptCount);
          break;
        case _SortField.collected:
          cmp = a.totalCollected.compareTo(b.totalCollected);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  Future<void> _pickDate(bool isStart) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showThemedDatePicker(context, initialDate: current);
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final rows = _buildReport();
    final totalCount = rows.fold(0, (sum, r) => sum + r.receiptCount);
    final totalCollected = rows.fold(0.0, (sum, r) => sum + r.totalCollected);

    return SortableReportScaffold<_ModeRow, _SortField>(
      title: 'Invoice Receipts Summary',
      isLoading: _isLoading,
      onRefresh: _fetchFromZoho,
      rows: rows,
      sortField: _sortField,
      sortAscending: _sortAscending,
      onSort: _toggleSort,
      startDate: _startDate,
      endDate: _endDate,
      onStartDateTap: () => _pickDate(true),
      onEndDateTap: () => _pickDate(false),
      onClearDate: () => setState(() {
        _startDate = null;
        _endDate = null;
      }),
      emptyIcon: Icons.account_balance_wallet_outlined,
      emptyTitle: 'No receipts',
      emptyMessage: 'No receipts recorded yet.',
      summaryChips: [
        ReportSummaryChip(
          label: 'Receipts',
          value: '$totalCount',
          color: AppTheme.infoSky,
        ),
        ReportSummaryChip(
          label: 'Total Collected',
          value: '$cs${totalCollected.toStringAsFixed(2)}',
          color: AppTheme.successEmerald,
        ),
      ],
      columns: const [
        ReportColumn(
          label: 'MODE',
          flex: 4,
          field: _SortField.mode,
          alignEnd: false,
        ),
        ReportColumn(label: 'COUNT', flex: 2, field: _SortField.count),
        ReportColumn(label: 'COLLECTED', flex: 4, field: _SortField.collected),
      ],
      exportHeaders: const [
        'Mode',
        'Count',
        'Collected',
        'Allocated',
        'Unallocated',
      ],
      exportRow: (row) => [
        row.mode,
        '${row.receiptCount}',
        row.totalCollected.toStringAsFixed(2),
        row.totalAllocated.toStringAsFixed(2),
        row.totalUnallocated.toStringAsFixed(2),
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
                      flex: 4,
                      child: Text(
                        row.mode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${row.receiptCount}',
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
                      flex: 4,
                      child: Text(
                        '$cs${row.totalCollected.toStringAsFixed(2)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.successEmerald,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Allocated: $cs${row.totalAllocated.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                    Text(
                      'Unallocated: $cs${row.totalUnallocated.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warningAmber,
                      ),
                    ),
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
