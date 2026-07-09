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
class SalesSummaryByCustomerItemReportPage extends StatefulWidget {
  const SalesSummaryByCustomerItemReportPage({super.key});

  @override
  State<SalesSummaryByCustomerItemReportPage> createState() =>
      _SalesSummaryByCustomerItemReportPageState();
}

class _SalesSummaryByCustomerItemReportPageState
    extends State<SalesSummaryByCustomerItemReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();

  DateTime? _startDate;
  DateTime? _endDate;
  _SortField _sortField = _SortField.amount;
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

  List<_CustomerItemRow> _buildReport() {
    final map = <String, _CustomerItemRow>{};

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
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
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
    final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

    return SortableReportScaffold<_CustomerItemRow, _SortField>(
      title: 'Sales by Customer & Item',
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
  }
}
