import 'package:flutter/material.dart';
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

/// Aggregated row for a single customer across the filtered sales returns.
class _CustomerReturnRow {
  final String customerId;
  final String customerName;
  int returnCount = 0;
  double totalRefunded = 0.0;

  _CustomerReturnRow({required this.customerId, required this.customerName});
}

enum _SortField { name, count, amount }

/// Full-screen customerwise sales-returns summary.
///
/// Fetches every sales return (credit note) live from Zoho Books and
/// aggregates them by customer, showing return count and total refunded.
/// Supports date-range filtering and column sorting.
class CustomerwiseReturnsSummaryReportPage extends StatefulWidget {
  const CustomerwiseReturnsSummaryReportPage({super.key});

  @override
  State<CustomerwiseReturnsSummaryReportPage> createState() =>
      _CustomerwiseReturnsSummaryReportPageState();
}

class _CustomerwiseReturnsSummaryReportPageState
    extends State<CustomerwiseReturnsSummaryReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();

  DateTime? _startDate;
  DateTime? _endDate;
  _SortField _sortField = _SortField.amount;
  bool _sortAscending = false;
  bool _isLoading = false;

  List<SalesReturn> _allReturns = [];

  @override
  void initState() {
    super.initState();
    _allReturns = _db.getLocalReturns();
    _fetchFromZoho();
  }

  Future<void> _fetchFromZoho() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final raw = await _apiClient.fetchSalesReturns();
      final returns = raw
          .map((json) => SalesReturnModel.fromJson(json))
          .toList();
      if (!mounted) return;
      setState(() {
        _allReturns = returns;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorSnackBar(context, 'Could not load report from Zoho: $e');
    }
  }

  List<_CustomerReturnRow> _buildReport() {
    final map = <String, _CustomerReturnRow>{};

    for (final ret in _allReturns) {
      final day = DateTime(ret.date.year, ret.date.month, ret.date.day);
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
        ret.customerId,
        () => _CustomerReturnRow(
          customerId: ret.customerId,
          customerName: ret.customerName,
        ),
      );
      row.returnCount++;
      row.totalRefunded += ret.total;
    }

    final rows = map.values.toList();
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.count:
          cmp = a.returnCount.compareTo(b.returnCount);
          break;
        case _SortField.amount:
          cmp = a.totalRefunded.compareTo(b.totalRefunded);
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
    final totalReturns = rows.fold(0, (sum, r) => sum + r.returnCount);
    final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

    return SortableReportScaffold<_CustomerReturnRow, _SortField>(
      title: 'Customerwise Returns Summary',
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
      emptyIcon: Icons.assignment_return_outlined,
      emptyTitle: 'No return data',
      emptyMessage: 'No sales returns recorded yet.',
      summaryChips: [
        ReportSummaryChip(
          label: 'Customers',
          value: '${rows.length}',
          color: AppTheme.infoSky,
        ),
        ReportSummaryChip(
          label: 'Returns',
          value: '$totalReturns',
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
          label: 'CUSTOMER',
          flex: 5,
          field: _SortField.name,
          alignEnd: false,
        ),
        ReportColumn(label: 'RETURNS', flex: 2, field: _SortField.count),
        ReportColumn(label: 'REFUNDED', flex: 3, field: _SortField.amount),
      ],
      exportHeaders: const ['Customer', 'Returns', 'Refunded'],
      exportRow: (row) => [
        row.customerName,
        '${row.returnCount}',
        row.totalRefunded.toStringAsFixed(2),
      ],
      itemBuilder: (context, row) {
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    row.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${row.returnCount}',
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
  }
}
