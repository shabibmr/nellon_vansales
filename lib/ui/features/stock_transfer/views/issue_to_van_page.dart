import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/warehouse.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/editor_footer.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../../../../ui/core/widgets/item_search_sheet.dart';
import '../bloc/stock_transfer_bloc.dart';

/// Issue-to-Van planning grid: loads stock from the organization's default
/// warehouse into the current van location.
///
/// Shows a 5-column grid (Current stock | Today's Invoices | Subtotal |
/// Extra to load | Grand total) so the salesperson can decide how much new
/// stock to bring aboard on top of what's already loaded and already sold.
class IssueToVanPage extends StatefulWidget {
  const IssueToVanPage({super.key});

  @override
  State<IssueToVanPage> createState() => _IssueToVanPageState();
}

class _IssueToVanPageState extends State<IssueToVanPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final TextEditingController _notesController = TextEditingController();
  final Map<String, TextEditingController> _extraControllers = {};

  @override
  void dispose() {
    _notesController.dispose();
    for (final c in _extraControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(StockTransferRow row) {
    return _extraControllers.putIfAbsent(
      row.item.id,
      () => TextEditingController(text: row.extraQty.toString()),
    );
  }

  Warehouse _resolveDefaultWarehouse() {
    final warehouses = _db.getWarehouses();
    if (warehouses.isEmpty) {
      return const Warehouse(id: '', name: 'Default Warehouse', address: '');
    }
    return warehouses.firstWhere(
      (w) => w.isPrimary,
      orElse: () => warehouses.first,
    );
  }

  Warehouse _resolveCurrentLocation() {
    final id = _db.assignedWarehouseId;
    final warehouses = _db.getWarehouses();
    return warehouses.firstWhere(
      (w) => w.id == id,
      orElse: () => Warehouse(id: id ?? '', name: 'Current Location', address: ''),
    );
  }

  Future<void> _openAddItemSheet(BuildContext pageContext) async {
    final bloc = pageContext.read<StockTransferBloc>();
    final excludedIds = bloc.state.rows.map((r) => r.item.id).toSet();
    final items = _db
        .getItems()
        .where((it) => !excludedIds.contains(it.id))
        .toList();

    Item? selected;
    await ItemSearchSheet.show<void>(
      pageContext,
      items: items,
      title: 'Add Extra Item',
      emptyMessage: 'No more items available to add',
      onSelected: (item, sheetContext) async {
        selected = item;
        Navigator.pop(sheetContext);
      },
    );

    if (selected == null || !mounted) return;
    final qty = await _promptQuantity(selected!.name);
    if (qty != null && qty > 0 && mounted) {
      bloc.add(AddExtraItem(item: selected!, quantity: qty));
    }
  }

  Future<int?> _promptQuantity(String itemName) async {
    final controller = TextEditingController(text: '1');
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Extra Qty — $itemName'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text) ?? 0),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultWarehouse = _resolveDefaultWarehouse();
    final currentLocation = _resolveCurrentLocation();

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Issue to Van')),
      body: SafeArea(
        child: BlocConsumer<StockTransferBloc, StockTransferState>(
          listenWhen: (previous, current) =>
              previous.successMessage != current.successMessage ||
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            if (state.successMessage != null) {
              showSuccessSnackBar(context, state.successMessage!);
              context.read<StockTransferBloc>().add(ClearMessages());
              Navigator.pop(context);
            } else if (state.errorMessage != null) {
              showErrorSnackBar(context, state.errorMessage!);
              context.read<StockTransferBloc>().add(ClearMessages());
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                if (state.isLoading)
                  const LinearProgressIndicator(color: AppTheme.primaryIndigo),
                _RouteHeader(
                  fromLabel: defaultWarehouse.name,
                  toLabel: currentLocation.name,
                  isDark: isDark,
                ),
                if (!state.isLiveData)
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
                  child: state.rows.isEmpty
                      ? const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No items to plan',
                          message:
                              'Sync masters or tap "Add Item" below to plan '
                              'today\'s issue to the van.',
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: MediaQuery.of(context).size.width,
                              ),
                              child: _buildGrid(context, state, isDark),
                            ),
                          ),
                        ),
                ),
                EditorFooter(
                  rows: [
                    (
                      label: 'Total Quantity to Issue:',
                      value: '${state.totalTransferQty}',
                      emphasize: true,
                    ),
                  ],
                  buttonLabel: 'ISSUE TO VAN',
                  buttonColor: AppTheme.primaryIndigo,
                  onSave: state.isLoading || state.totalTransferQty <= 0
                      ? null
                      : () {
                          context.read<StockTransferBloc>().add(
                            SubmitTransfer(notes: _notesController.text),
                          );
                        },
                  trailing: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openAddItemSheet(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Item'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryIndigo,
                        side: const BorderSide(color: AppTheme.primaryIndigo),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, StockTransferState state, bool isDark) {
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
    );
    const cellPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    Widget headerCell(String label, {Alignment align = Alignment.centerLeft}) =>
        Container(
          padding: cellPadding,
          alignment: align,
          child: Text(label, style: headerStyle),
        );

    Widget dataCell(Widget child, {Alignment align = Alignment.center}) =>
        Container(
          padding: cellPadding,
          alignment: align,
          child: child,
        );

    return Table(
      border: TableBorder.symmetric(inside: BorderSide(color: borderColor)),
      columnWidths: const {
        0: FixedColumnWidth(180),
        1: FixedColumnWidth(90),
        2: FixedColumnWidth(90),
        3: FixedColumnWidth(90),
        4: FixedColumnWidth(110),
        5: FixedColumnWidth(90),
        6: FixedColumnWidth(48),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          ),
          children: [
            headerCell('Item'),
            headerCell('Current\n(1)', align: Alignment.center),
            headerCell('Invoices\n(2)', align: Alignment.center),
            headerCell('Total\n(3)', align: Alignment.center),
            headerCell('Extra\n(4)', align: Alignment.center),
            headerCell('Grand\n(5)', align: Alignment.center),
            const SizedBox.shrink(),
          ],
        ),
        for (final row in state.rows)
          TableRow(
            children: [
              dataCell(
                Text(
                  row.item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                align: Alignment.centerLeft,
              ),
              dataCell(Text('${row.currentStock}')),
              dataCell(Text('${row.invoiceQty}')),
              dataCell(
                Text(
                  '${row.subtotal}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              dataCell(
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _controllerFor(row),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) {
                      context.read<StockTransferBloc>().add(
                        UpdateExtraQty(
                          itemId: row.item.id,
                          quantity: int.tryParse(val) ?? 0,
                        ),
                      );
                    },
                  ),
                ),
              ),
              dataCell(
                Text(
                  '${row.grandTotal}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryIndigo,
                  ),
                ),
              ),
              dataCell(
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.errorRose,
                  ),
                  onPressed: () {
                    _extraControllers.remove(row.item.id)?.dispose();
                    context.read<StockTransferBloc>().add(
                      RemoveRow(row.item.id),
                    );
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _RouteHeader extends StatelessWidget {
  final String fromLabel;
  final String toLabel;
  final bool isDark;

  const _RouteHeader({
    required this.fromLabel,
    required this.toLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color(0xFF334155)
                : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              fromLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: AppTheme.primaryIndigo,
          ),
          Expanded(
            child: Text(
              toLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
