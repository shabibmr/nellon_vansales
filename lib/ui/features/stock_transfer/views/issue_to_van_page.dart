import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/repositories/item_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/date_filter.dart';
import '../../../../ui/core/utils/quantity_format.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/editor_footer.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../../../../ui/core/widgets/item_search_sheet.dart';
import '../bloc/stock_transfer_bloc.dart';

/// Issue-to-Van planning grid: loads stock from the organization's default
/// warehouse into the current van location.
///
/// Shows current van stock, extra to load, and resulting grand total. The
/// transfer date is displayed read-only (today).
class IssueToVanPage extends StatefulWidget {
  const IssueToVanPage({super.key});

  @override
  State<IssueToVanPage> createState() => _IssueToVanPageState();
}

class _IssueToVanPageState extends State<IssueToVanPage> {
  final TextEditingController _notesController = TextEditingController();
  final Map<String, TextEditingController> _extraControllers = {};
  final DateTime _issueDate = todayDate();
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

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
      () => TextEditingController(text: formatQuantity(row.extraQtyEntered)),
    );
  }

  Future<void> _openAddItemSheet(BuildContext pageContext) async {
    final bloc = pageContext.read<StockTransferBloc>();
    final excludedIds = bloc.state.rows.map((r) => r.item.id).toSet();
    final items = pageContext
        .read<ItemRepository>()
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
    final entry = await _promptQuantity(selected!);
    if (entry != null && entry.quantity > 0 && mounted) {
      bloc.add(
        AddExtraItem(
          item: selected!,
          quantity: entry.quantity,
          uom: entry.uom,
          conversionRate: entry.conversionRate,
        ),
      );
    }
  }

  /// Prompts for a quantity and (for multi-UOM items) the unit it is entered
  /// in. Returns null when cancelled.
  Future<({double quantity, String uom, double conversionRate})?>
      _promptQuantity(Item item) async {
    final controller = TextEditingController(text: '1');
    final unitOptions = [
      if (item.uom.trim().isNotEmpty) item.uom.trim(),
      ...item.unitConversions.map((c) => c.targetUnit),
    ];
    var selectedUom = unitOptions.isNotEmpty ? unitOptions.first : '';
    final result =
        await showDialog<({double quantity, String uom, double conversionRate})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final decimals =
              item.conversionFor(selectedUom)?.quantityDecimalPlaces ?? 3;
          return AlertDialog(
            title: Text('Extra Qty — ${item.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: decimals > 0
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  autofocus: true,
                  inputFormatters: [
                    decimals > 0
                        ? FilteringTextInputFormatter.allow(
                            RegExp('^\\d*\\.?\\d{0,$decimals}'),
                          )
                        : FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                if (unitOptions.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUom,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      isDense: true,
                    ),
                    items: unitOptions
                        .map(
                          (u) => DropdownMenuItem<String>(
                            value: u,
                            child: Text(u, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (u) {
                      if (u != null) setDialogState(() => selectedUom = u);
                    },
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (
                  quantity: double.tryParse(controller.text) ?? 0,
                  uom: selectedUom,
                  conversionRate: item.conversionRateFor(selectedUom),
                )),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  fromLabel: state.defaultWarehouse.name,
                  toLabel: state.currentLocation.name,
                  dateLabel: _dateFormat.format(_issueDate),
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
                if (!state.isLoading && state.defaultWarehouse.id.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: AppTheme.errorRose.withValues(alpha: 0.12),
                    child: const Text(
                      'Primary location is not configured in Zoho. '
                      'Contact your administrator — Issue to Van is disabled '
                      'until this is fixed.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.errorRose,
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
                                minWidth: MediaQuery.sizeOf(context).width,
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
                      value: formatQuantity(state.totalTransferQty),
                      emphasize: true,
                    ),
                  ],
                  buttonLabel: 'ISSUE TO VAN',
                  buttonColor: AppTheme.primaryIndigo,
                  onSave: state.isLoading ||
                          state.totalTransferQty <= 0 ||
                          state.defaultWarehouse.id.isEmpty
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

  /// Editable extra-quantity cell: a qty field entered in the row's selected
  /// unit, plus a compact unit dropdown for multi-UOM items.
  Widget _buildExtraQtyCell(BuildContext context, StockTransferRow row) {
    final unitOptions = [
      if (row.item.uom.trim().isNotEmpty) row.item.uom.trim(),
      ...row.item.unitConversions.map((c) => c.targetUnit),
    ];
    final selUom = row.displayUom;
    final decimals =
        row.item.conversionFor(selUom)?.quantityDecimalPlaces ?? 3;

    final qtyField = SizedBox(
      width: 70,
      child: TextField(
        controller: _controllerFor(row),
        keyboardType: decimals > 0
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          decimals > 0
              ? FilteringTextInputFormatter.allow(
                  RegExp('^\\d*\\.?\\d{0,$decimals}'),
                )
              : FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: (val) {
          context.read<StockTransferBloc>().add(
            UpdateExtraQty(
              itemId: row.item.id,
              quantity: double.tryParse(val) ?? 0,
            ),
          );
        },
      ),
    );

    if (unitOptions.length <= 1) return qtyField;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        qtyField,
        SizedBox(
          height: 28,
          child: DropdownButton<String>(
            value: unitOptions.contains(selUom) ? selUom : unitOptions.first,
            isDense: true,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
            items: unitOptions
                .map(
                  (u) => DropdownMenuItem<String>(
                    value: u,
                    child: Text(u, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (u) {
              if (u == null) return;
              context.read<StockTransferBloc>().add(
                UpdateRowUnit(
                  itemId: row.item.id,
                  uom: u,
                  conversionRate: row.item.conversionRateFor(u),
                ),
              );
              // Re-express the entered quantity in the new unit.
              final rate = row.item.conversionRateFor(u);
              final entered = rate > 0 ? row.extraQty / rate : row.extraQty;
              _extraControllers[row.item.id]?.text =
                  row.extraQty > 0 ? formatQuantity(entered) : '';
            },
          ),
        ),
      ],
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
        2: FixedColumnWidth(110),
        3: FixedColumnWidth(90),
        4: FixedColumnWidth(48),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          ),
          children: [
            headerCell('Item'),
            headerCell('Current', align: Alignment.center),
            headerCell('Extra', align: Alignment.center),
            headerCell('Grand', align: Alignment.center),
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
              dataCell(Text(formatQuantity(row.currentStock))),
              dataCell(_buildExtraQtyCell(context, row)),
              dataCell(
                Text(
                  formatQuantity(row.grandTotal),
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
  final String dateLabel;
  final bool isDark;

  const _RouteHeader({
    required this.fromLabel,
    required this.toLabel,
    required this.dateLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fromLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 16, color: secondary),
              const SizedBox(width: 6),
              Text(
                'Date',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
              const Spacer(),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
