import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/item_model.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/item.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/currency.dart';
import '../../../core/cubit/list_filter_cubit.dart';
import '../../../core/widgets/sortable_report_scaffold.dart';
import '../bloc/report_bloc.dart';
import '../bloc/report_event.dart';
import '../bloc/report_state.dart';
import '../widgets/report_bloc_host.dart';

enum _SortField { name, rate, stock }

/// Full-screen van stock report page.
///
/// Lists items with name, rate and available quantity, scoped to the
/// location mapped to the logged-in salesperson (`assigned_warehouse_id`).
/// Fetches live location-filtered stock from Zoho when online and falls
/// back to the locally cached item list when offline.
///
/// Includes a live search field (name / SKU) via [ListFilterCubit].
class StockReportPage extends StatelessWidget {
  const StockReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportBlocHost<Item>(
      create: (_) => ReportBloc<Item>(
        getLocal: () => sl<HiveDatabaseService>().getItems(),
        fetchRemote: () async {
          final locationId = sl<HiveDatabaseService>().assignedWarehouseId;
          final raw = await sl<ZohoApiClient>().fetchItems(locationId ?? '');
          return raw.map<Item>((j) => ItemModel.fromJson(j)).toList();
        },
        initialSortField: _SortField.name,
        initialSortAscending: true,
      ),
      builder: (context, state) => _StockReportBody(state: state),
    );
  }
}

class _StockReportBody extends StatefulWidget {
  final ReportState<Item> state;

  const _StockReportBody({required this.state});

  @override
  State<_StockReportBody> createState() => _StockReportBodyState();
}

class _StockReportBodyState extends State<_StockReportBody> {
  late final ListFilterCubit<Item> _filterCubit;
  final _searchController = TextEditingController();

  static bool _matches(Item item, String query) {
    final q = query.toLowerCase();
    return item.name.toLowerCase().contains(q) ||
        item.sku.toLowerCase().contains(q);
  }

  @override
  void initState() {
    super.initState();
    _filterCubit = ListFilterCubit<Item>(
      initialItems: widget.state.rows,
      filterPredicate: _matches,
    );
  }

  @override
  void didUpdateWidget(covariant _StockReportBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.rows != widget.state.rows) {
      _filterCubit.setItems(widget.state.rows);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = context.org.currencySymbol;
    final reportState = widget.state;
    final sortField = reportState.sortField as _SortField? ?? _SortField.name;
    final sortAscending = reportState.sortAscending;

    return BlocProvider<ListFilterCubit<Item>>.value(
      value: _filterCubit,
      child: BlocBuilder<ListFilterCubit<Item>, ListFilterState<Item>>(
        builder: (context, filterState) {
          final items = [...filterState.filteredItems]
            ..sort((a, b) {
              final cmp = switch (sortField) {
                _SortField.name => a.name.compareTo(b.name),
                _SortField.rate => a.rate.compareTo(b.rate),
                _SortField.stock => a.stock.compareTo(b.stock),
              };
              return sortAscending ? cmp : -cmp;
            });

          final hasQuery = filterState.query.trim().isNotEmpty;

          return SortableReportScaffold<Item, _SortField>(
            title: 'Stock Report',
            isLoading: reportState.isLoading,
            onRefresh: () =>
                context.read<ReportBloc<Item>>().add(const RefreshReport()),
            rows: items,
            sortField: sortField,
            sortAscending: sortAscending,
            onSort: (field) {
              final bloc = context.read<ReportBloc<Item>>();
              if (bloc.state.sortField == field) {
                bloc.add(SetSort(field));
              } else {
                bloc.add(SetSort(field, ascending: field == _SortField.name));
              }
            },
            emptyIcon: Icons.inventory_2_outlined,
            emptyTitle: hasQuery ? 'No matching items' : 'No stock found',
            emptyMessage: hasQuery
                ? 'No items match "${filterState.query.trim()}".\n'
                    'Try a different name or SKU.'
                : 'No items are available for your assigned location.\n'
                    'Sync masters or check your location mapping.',
            banner: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!reportState.isLiveData)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      context.read<ListFilterCubit<Item>>().setQuery(value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search items by name or SKU…',
                    isDense: true,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppTheme.primaryIndigo,
                    ),
                    suffixIcon: hasQuery
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: Icon(
                              Icons.cancel,
                              size: 20,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              context.read<ListFilterCubit<Item>>().setQuery('');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
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
                    backgroundColor:
                        AppTheme.primaryIndigo.withValues(alpha: 0.1),
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
                    'SKU: ${item.sku} · Rate: ${formatCurrency(item.rate, cs)}',
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}
