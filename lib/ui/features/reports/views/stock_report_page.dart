import 'package:flutter/material.dart';
import '../../../../data/models/item_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';

enum _SortField { name, rate, stock }

/// Full-screen van stock report page.
///
/// Lists items with name, rate and available quantity, scoped to the
/// location mapped to the logged-in salesperson (`assigned_warehouse_id`).
/// Fetches live location-filtered stock from Zoho when online and falls
/// back to the locally cached item list when offline.
class StockReportPage extends StatefulWidget {
  const StockReportPage({super.key});

  @override
  State<StockReportPage> createState() => _StockReportPageState();
}

class _StockReportPageState extends State<StockReportPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final ZohoApiClient _api = sl<ZohoApiClient>();

  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;
  List<Item> _items = [];
  bool _isLoading = true;
  bool _isLiveData = false;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    setState(() => _isLoading = true);
    final locationId = _db.assignedWarehouseId;
    List<Item> items;
    var live = false;
    try {
      final raw = await _api.fetchItems(locationId ?? '');
      items = raw.map<Item>((j) => ItemModel.fromJson(j)).toList();
      live = true;
    } catch (_) {
      // Offline: fall back to the locally synced (location-scoped) cache.
      items = _db.getItems();
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLiveData = live;
      _isLoading = false;
    });
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = field == _SortField.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    final items = [..._items]
      ..sort((a, b) {
        final cmp = switch (_sortField) {
          _SortField.name => a.name.compareTo(b.name),
          _SortField.rate => a.rate.compareTo(b.rate),
          _SortField.stock => a.stock.compareTo(b.stock),
        };
        return _sortAscending ? cmp : -cmp;
      });

    return SortableReportScaffold<Item, _SortField>(
      title: 'Stock Report',
      isLoading: _isLoading,
      onRefresh: _loadStock,
      rows: items,
      sortField: _sortField,
      sortAscending: _sortAscending,
      onSort: _toggleSort,
      emptyIcon: Icons.inventory_2_outlined,
      emptyTitle: 'No stock found',
      emptyMessage:
          'No items are available for your assigned location.\n'
          'Sync masters or check your location mapping.',
      banner: _isLiveData
          ? null
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warningAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Offline — showing last synced stock',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warningAmber,
                ),
              ),
            ),
      columns: const [
        ReportColumn(
          label: 'ITEM',
          flex: 5,
          field: _SortField.name,
          alignEnd: false,
        ),
        ReportColumn(label: 'RATE', flex: 3, field: _SortField.rate),
        ReportColumn(label: 'STOCK', flex: 2, field: _SortField.stock),
      ],
      exportHeaders: const ['Item', 'Rate', 'Stock'],
      exportRow: (item) => [
        item.name,
        item.rate.toStringAsFixed(2),
        '${item.stock}',
      ],
      itemBuilder: (context, item) {
        final outOfStock = item.stock <= 0;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.1),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppTheme.primaryIndigo,
                size: 20,
              ),
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              'Rate: ${formatCurrency(item.rate, cs)}',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
            trailing: Text(
              '${item.stock}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: outOfStock ? AppTheme.errorRose : AppTheme.successEmerald,
              ),
            ),
          ),
        );
      },
    );
  }
}
