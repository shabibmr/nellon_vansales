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
class ItemwiseReturnsSummaryReportPage extends StatefulWidget {
  const ItemwiseReturnsSummaryReportPage({super.key});

  @override
  State<ItemwiseReturnsSummaryReportPage> createState() =>
      _ItemwiseReturnsSummaryReportPageState();
}

class _ItemwiseReturnsSummaryReportPageState
    extends State<ItemwiseReturnsSummaryReportPage> {
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

  List<_ItemReturnRow> _buildReport() {
    final map = <String, _ItemReturnRow>{};

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
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
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
    final totalQty = rows.fold(0, (sum, r) => sum + r.totalQty);
    final totalRefunded = rows.fold(0.0, (sum, r) => sum + r.totalRefunded);

    return SortableReportScaffold<_ItemReturnRow, _SortField>(
      title: 'Itemwise Returns Summary',
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
  }
}
