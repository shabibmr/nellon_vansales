import 'package:flutter/material.dart';
import '../../../../data/models/item_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../../ui/core/widgets/empty_state.dart';

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
    items.sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLiveData = live;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Stock Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh stock',
            onPressed: _isLoading ? null : _loadStock,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
            )
          : _items.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No stock found',
              message:
                  'No items are available for your assigned location.\n'
                  'Sync masters or check your location mapping.',
            )
          : RefreshIndicator(
              onRefresh: _loadStock,
              color: AppTheme.primaryIndigo,
              child: Column(
                children: [
                  if (!_isLiveData)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: AppTheme.warningAmber.withValues(alpha: 0.12),
                      child: const Text(
                        'Offline — showing last synced stock',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warningAmber,
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final outOfStock = item.stock <= 0;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryIndigo.withValues(
                              alpha: 0.1,
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: AppTheme.primaryIndigo,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
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
                              color: outOfStock
                                  ? AppTheme.errorRose
                                  : AppTheme.successEmerald,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
