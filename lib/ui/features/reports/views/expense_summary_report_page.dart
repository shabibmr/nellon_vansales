import 'package:flutter/material.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';

/// Aggregated row for a single expense category across the filtered period.
class _CategoryRow {
  final String category;
  int entryCount = 0;
  double totalAmount = 0.0;

  _CategoryRow({required this.category});
}

enum _SortField { category, count, amount }

/// Full-screen expense summary, grouped by ledger category.
///
/// Fetches every expense (with itemized lines) live from Zoho Books and
/// aggregates them by category, showing entry count and total amount per
/// category. Supports date-range filtering and column sorting. The local
/// expense cache is painted instantly on open while the live fetch is in
/// flight.
class ExpenseSummaryReportPage extends StatefulWidget {
  const ExpenseSummaryReportPage({super.key});

  @override
  State<ExpenseSummaryReportPage> createState() =>
      _ExpenseSummaryReportPageState();
}

class _ExpenseSummaryReportPageState extends State<ExpenseSummaryReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();

  DateTime? _startDate;
  DateTime? _endDate;
  _SortField _sortField = _SortField.amount;
  bool _sortAscending = false;
  bool _isLoading = false;

  List<ExpenseEntry> _allExpenses = [];

  @override
  void initState() {
    super.initState();
    _allExpenses = _db.getLocalExpenses();
    _fetchFromZoho();
  }

  /// Zoho's raw expense JSON uses `line_items`/`account_name`; the local
  /// [ExpenseEntryModel] expects `lines`/`category`. Adapt just enough of the
  /// shape so aggregation-by-category reflects Zoho's actual ledger accounts.
  Map<String, dynamic> _normalizeExpenseJson(Map<String, dynamic> json) {
    final lineItems = (json['line_items'] as List?) ?? const [];
    return {
      ...json,
      'lines': lineItems
          .whereType<Map>()
          .map(
            (l) => {
              'category': l['account_name'] ?? 'Miscellaneous',
              'amount': l['amount'] ?? 0.0,
              'description': l['description'] ?? '',
            },
          )
          .toList(),
    };
  }

  Future<void> _fetchFromZoho() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final raw = await _apiClient.fetchExpenses();
      final expenses = raw
          .map((json) => ExpenseEntryModel.fromJson(_normalizeExpenseJson(json)))
          .toList();
      if (!mounted) return;
      setState(() {
        _allExpenses = expenses;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorSnackBar(context, 'Could not load report from Zoho: $e');
    }
  }

  List<_CategoryRow> _buildReport() {
    final map = <String, _CategoryRow>{};

    for (final entry in _allExpenses) {
      final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
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

      for (final line in entry.lines) {
        final row = map.putIfAbsent(
          line.category,
          () => _CategoryRow(category: line.category),
        );
        row.entryCount++;
        row.totalAmount += line.amount;
      }
    }

    final rows = map.values.toList();
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.category:
          cmp = a.category.compareTo(b.category);
          break;
        case _SortField.count:
          cmp = a.entryCount.compareTo(b.entryCount);
          break;
        case _SortField.amount:
          cmp = a.totalAmount.compareTo(b.totalAmount);
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
    final cs = context.org.currencySymbol;
    final rows = _buildReport();
    final totalCount = rows.fold(0, (sum, r) => sum + r.entryCount);
    final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

    return SortableReportScaffold<_CategoryRow, _SortField>(
      title: 'Expense Summary',
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
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No expenses',
      emptyMessage: 'No expenses recorded yet.',
      summaryChips: [
        ReportSummaryChip(
          label: 'Categories',
          value: '${rows.length}',
          color: AppTheme.infoSky,
        ),
        ReportSummaryChip(
          label: 'Entries',
          value: '$totalCount',
          color: AppTheme.primaryIndigo,
        ),
        ReportSummaryChip(
          label: 'Total',
          value: '$cs${totalAmount.toStringAsFixed(2)}',
          color: AppTheme.errorRose,
        ),
      ],
      columns: const [
        ReportColumn(
          label: 'CATEGORY',
          flex: 5,
          field: _SortField.category,
          alignEnd: false,
        ),
        ReportColumn(label: 'ENTRIES', flex: 2, field: _SortField.count),
        ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
      ],
      exportHeaders: const ['Category', 'Entries', 'Amount'],
      exportRow: (row) => [
        row.category,
        '${row.entryCount}',
        row.totalAmount.toStringAsFixed(2),
      ],
      itemBuilder: (context, row) {
        final pct = totalAmount > 0 ? (row.totalAmount / totalAmount) : 0.0;
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
                        row.category,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${row.entryCount}',
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
                        '$cs${row.totalAmount.toStringAsFixed(2)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.errorRose,
                        ),
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
                    color: AppTheme.errorRose,
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
