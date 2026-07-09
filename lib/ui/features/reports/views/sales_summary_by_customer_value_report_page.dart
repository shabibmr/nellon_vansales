import 'package:flutter/material.dart';
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

/// Aggregated row for a single customer across the filtered invoices.
class _CustomerRow {
  final String customerId;
  final String customerName;
  int invoiceCount = 0;
  double totalValue = 0.0;

  _CustomerRow({required this.customerId, required this.customerName});
}

enum _SortField { name, count, value }

/// Full-screen sales-by-customer (value) summary.
///
/// Fetches every invoice live from Zoho Books and aggregates them by
/// customer, showing invoice count and total value per customer. Supports
/// date-range filtering and column sorting.
class SalesSummaryByCustomerValueReportPage extends StatefulWidget {
  const SalesSummaryByCustomerValueReportPage({super.key});

  @override
  State<SalesSummaryByCustomerValueReportPage> createState() =>
      _SalesSummaryByCustomerValueReportPageState();
}

class _SalesSummaryByCustomerValueReportPageState
    extends State<SalesSummaryByCustomerValueReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();

  DateTime? _startDate;
  DateTime? _endDate;
  _SortField _sortField = _SortField.value;
  bool _sortAscending = false;
  bool _isLoading = false;

  List<SalesInvoice> _allInvoices = [];

  @override
  void initState() {
    super.initState();
    _allInvoices = _db.getLocalInvoices();
    _fetchFromZoho();
  }

  Future<void> _fetchFromZoho() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final raw = await _apiClient.fetchInvoices();
      final invoices = raw
          .map((json) => SalesInvoiceModel.fromJson(json))
          .toList();
      if (!mounted) return;
      setState(() {
        _allInvoices = invoices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorSnackBar(context, 'Could not load report from Zoho: $e');
    }
  }

  List<_CustomerRow> _buildReport() {
    final map = <String, _CustomerRow>{};

    for (final inv in _allInvoices) {
      final day = DateTime(inv.date.year, inv.date.month, inv.date.day);
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
        inv.customerId,
        () => _CustomerRow(
          customerId: inv.customerId,
          customerName: inv.customerName,
        ),
      );
      row.invoiceCount++;
      row.totalValue += inv.total;
    }

    final rows = map.values.toList();
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.name:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.count:
          cmp = a.invoiceCount.compareTo(b.invoiceCount);
          break;
        case _SortField.value:
          cmp = a.totalValue.compareTo(b.totalValue);
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
    final totalInvoices = rows.fold(0, (sum, r) => sum + r.invoiceCount);
    final totalValue = rows.fold(0.0, (sum, r) => sum + r.totalValue);

    return SortableReportScaffold<_CustomerRow, _SortField>(
      title: 'Sales Summary by Customer',
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
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No sales data',
      emptyMessage: 'No invoices recorded yet.',
      summaryChips: [
        ReportSummaryChip(
          label: 'Customers',
          value: '${rows.length}',
          color: AppTheme.infoSky,
        ),
        ReportSummaryChip(
          label: 'Invoices',
          value: '$totalInvoices',
          color: AppTheme.primaryIndigo,
        ),
        ReportSummaryChip(
          label: 'Total',
          value: '$cs${totalValue.toStringAsFixed(2)}',
          color: AppTheme.successEmerald,
        ),
      ],
      columns: const [
        ReportColumn(
          label: 'CUSTOMER',
          flex: 5,
          field: _SortField.name,
          alignEnd: false,
        ),
        ReportColumn(label: 'INVOICES', flex: 2, field: _SortField.count),
        ReportColumn(label: 'VALUE', flex: 3, field: _SortField.value),
      ],
      itemBuilder: (context, row) {
        final pct = totalValue > 0 ? (row.totalValue / totalValue) : 0.0;
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
                        '${row.invoiceCount}',
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
                        '$cs${row.totalValue.toStringAsFixed(2)}',
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
                const SizedBox(height: 8),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
