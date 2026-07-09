import 'package:flutter/material.dart';
import '../../../../data/models/expense_entry_model.dart';
import '../../../../data/models/receipt_voucher_model.dart';
import '../../../../data/models/sales_invoice_model.dart';
import '../../../../data/models/sales_return_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/expense_entry.dart';
import '../../../../domain/models/receipt_voucher.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_return.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_picker.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';

/// Aggregated row for a single transaction type across the filtered period.
class _TypeRow {
  final String type;
  final IconData icon;
  final Color color;
  int count = 0;
  double totalAmount = 0.0;

  _TypeRow({required this.type, required this.icon, required this.color});
}

enum _SortField { type, count, amount }

/// Full-screen "Aggregate of All" transactions summary.
///
/// Fetches invoices, receipts, expenses, and sales returns live from Zoho in
/// parallel and rolls each up into one row per transaction type within the
/// selected date range. The local cache is painted instantly on open while
/// the live fetch is in flight.
class TransactionsSummaryReportPage extends StatefulWidget {
  const TransactionsSummaryReportPage({super.key});

  @override
  State<TransactionsSummaryReportPage> createState() =>
      _TransactionsSummaryReportPageState();
}

class _TransactionsSummaryReportPageState
    extends State<TransactionsSummaryReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _apiClient = sl<ZohoApiClient>();

  DateTime? _startDate;
  DateTime? _endDate;
  _SortField _sortField = _SortField.amount;
  bool _sortAscending = false;
  bool _isLoading = false;

  List<SalesInvoice> _invoices = [];
  List<ReceiptVoucher> _receipts = [];
  List<ExpenseEntry> _expenses = [];
  List<SalesReturn> _returns = [];

  @override
  void initState() {
    super.initState();
    _invoices = _db.getLocalInvoices();
    _receipts = _db.getLocalReceipts();
    _expenses = _db.getLocalExpenses();
    _returns = _db.getLocalReturns();
    _fetchFromZoho();
  }

  Future<void> _fetchFromZoho() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiClient.fetchInvoices(),
        _apiClient.fetchReceipts(),
        _apiClient.fetchExpenses(),
        _apiClient.fetchSalesReturns(),
      ]);
      if (!mounted) return;
      setState(() {
        _invoices = (results[0])
            .map((j) => SalesInvoiceModel.fromJson(j))
            .toList();
        _receipts = (results[1])
            .map((j) => ReceiptVoucherModel.fromJson(j))
            .toList();
        _expenses = (results[2])
            .map((j) => ExpenseEntryModel.fromJson(_normalizeExpenseJson(j)))
            .toList();
        _returns = (results[3])
            .map((j) => SalesReturnModel.fromJson(j))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorSnackBar(context, 'Could not load report from Zoho: $e');
    }
  }

  /// Zoho's raw expense JSON uses `line_items`/`account_name`; the local
  /// [ExpenseEntryModel] expects `lines`/`category`. Adapt just enough of the
  /// shape for count/amount aggregation (category labels come through as
  /// Zoho's ledger account names rather than the app's fixed category set).
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

  bool _inRange(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (_startDate != null) {
      final s = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      if (day.isBefore(s)) return false;
    }
    if (_endDate != null) {
      final e = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      if (day.isAfter(e)) return false;
    }
    return true;
  }

  List<_TypeRow> _buildReport() {
    final invoiceRow = _TypeRow(
      type: 'Invoices',
      icon: Icons.receipt_long_rounded,
      color: AppTheme.primaryIndigo,
    );
    final receiptRow = _TypeRow(
      type: 'Receipts',
      icon: Icons.account_balance_wallet_rounded,
      color: AppTheme.successEmerald,
    );
    final expenseRow = _TypeRow(
      type: 'Expenses',
      icon: Icons.local_gas_station_rounded,
      color: AppTheme.errorRose,
    );
    final returnRow = _TypeRow(
      type: 'Sales Returns',
      icon: Icons.assignment_return_rounded,
      color: AppTheme.warningAmber,
    );

    for (final inv in _invoices) {
      if (!_inRange(inv.date)) continue;
      invoiceRow.count++;
      invoiceRow.totalAmount += inv.total;
    }
    for (final rcpt in _receipts) {
      if (!_inRange(rcpt.date)) continue;
      receiptRow.count++;
      receiptRow.totalAmount += rcpt.amount;
    }
    for (final exp in _expenses) {
      if (!_inRange(exp.date)) continue;
      expenseRow.count++;
      expenseRow.totalAmount += exp.amount;
    }
    for (final ret in _returns) {
      if (!_inRange(ret.date)) continue;
      returnRow.count++;
      returnRow.totalAmount += ret.total;
    }

    final rows = [invoiceRow, receiptRow, expenseRow, returnRow];
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.type:
          cmp = a.type.compareTo(b.type);
          break;
        case _SortField.count:
          cmp = a.count.compareTo(b.count);
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

    final totalCount = rows.fold(0, (sum, r) => sum + r.count);
    final totalAmount = rows.fold(0.0, (sum, r) => sum + r.totalAmount);

    return SortableReportScaffold<_TypeRow, _SortField>(
      title: 'Transactions Summary',
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
      emptyTitle: 'No transactions',
      emptyMessage: 'No transactions recorded yet.',
      summaryChips: [
        ReportSummaryChip(
          label: 'Transactions',
          value: '$totalCount',
          color: AppTheme.infoSky,
        ),
        ReportSummaryChip(
          label: 'Total Value',
          value: '$cs${totalAmount.toStringAsFixed(2)}',
          color: AppTheme.primaryIndigo,
        ),
      ],
      columns: const [
        ReportColumn(
          label: 'TYPE',
          flex: 5,
          field: _SortField.type,
          alignEnd: false,
        ),
        ReportColumn(label: 'COUNT', flex: 2, field: _SortField.count),
        ReportColumn(label: 'AMOUNT', flex: 3, field: _SortField.amount),
      ],
      itemBuilder: (context, row) {
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: row.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(row.icon, color: row.color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Text(
                    row.type,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${row.count}',
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: row.color,
                    ),
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
