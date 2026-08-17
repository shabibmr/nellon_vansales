import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../domain/models/item.dart';
import '../../../../domain/models/stock_transfer.dart';
import '../../../../domain/repositories/item_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_filter.dart';
import '../../../core/utils/quantity_format.dart';
import '../../../core/utils/snackbars.dart';
import '../../../core/widgets/editor_footer.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/item_search_sheet.dart';
import '../bloc/stock_transfer_bloc.dart';
import '../widgets/stock_transfer_line_tile.dart';
import '../widgets/stock_transfer_qty_dialog.dart';
import '../widgets/stock_transfer_route_header.dart';

/// Shared editor body for both Issue-to-Van and Stock-Unloading, driven by
/// [StockTransferBloc]. New grids are loaded by the page `open` factories
/// before this view mounts. An "Add Item" button covers items not
/// already listed.
///
/// When [existingTransfer] is provided, this page instead re-opens that
/// transfer for viewing/editing: it dispatches [LoadIssueGridForEdit] /
/// [LoadUnloadGridForEdit] itself on init, pre-fills quantities/notes/date
/// from the transfer, and locks to read-only once Zoho reports any status
/// other than `draft`.
class StockTransferEditorView extends StatefulWidget {
  final bool isLoad;
  final StockTransfer? existingTransfer;

  const StockTransferEditorView({
    super.key,
    required this.isLoad,
    this.existingTransfer,
  });

  @override
  State<StockTransferEditorView> createState() =>
      _StockTransferEditorViewState();
}

class _StockTransferEditorViewState extends State<StockTransferEditorView> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  late final TextEditingController _notesController;
  late final DateTime _issueDate;

  String get _title {
    final existing = widget.existingTransfer;
    if (existing == null) {
      return widget.isLoad ? 'Issue to Van' : 'Stock Unloading';
    }
    return existing.transferNumber.isNotEmpty
        ? existing.transferNumber
        : existing.id;
  }

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: widget.existingTransfer?.notes ?? '',
    );
    _issueDate = widget.existingTransfer?.date ?? todayDate();
    final existing = widget.existingTransfer;
    if (existing != null) {
      final bloc = context.read<StockTransferBloc>();
      if (widget.isLoad) {
        bloc.add(LoadIssueGridForEdit(existing));
      } else {
        bloc.add(LoadUnloadGridForEdit(existing));
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _editRowQty(StockTransferRow row) async {
    final result = await StockTransferQtyDialog.show(
      context,
      item: row.item,
      initialQuantity: row.extraQty,
      initialUom: row.displayUom,
      currentStock: row.currentStock,
    );
    if (result == null || !mounted) return;
    final bloc = context.read<StockTransferBloc>();
    bloc.add(
      UpdateRowUnit(
        itemId: row.item.id,
        uom: result.uom,
        conversionRate: result.conversionRate,
      ),
    );
    bloc.add(UpdateExtraQty(itemId: row.item.id, quantity: result.quantity));
  }

  Future<void> _openAddItemSheet() async {
    final bloc = context.read<StockTransferBloc>();
    final excludedIds = bloc.state.rows.map((r) => r.item.id).toSet();
    final items = context
        .read<ItemRepository>()
        .getItems()
        .where((it) => !excludedIds.contains(it.id))
        .toList();

    Item? selected;
    await ItemSearchSheet.show<void>(
      context,
      items: items,
      title: 'Add Item',
      emptyMessage: 'No more items available to add',
      onSelected: (item, sheetContext) async {
        selected = item;
        Navigator.pop(sheetContext);
      },
    );

    if (selected == null || !mounted) return;
    final result = await StockTransferQtyDialog.show(
      context,
      item: selected!,
      currentStock: selected!.stock,
    );
    if (result != null && result.quantity > 0 && mounted) {
      bloc.add(
        AddExtraItem(
          item: selected!,
          quantity: result.quantity,
          uom: result.uom,
          conversionRate: result.conversionRate,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(title: Text(_title)),
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
            final readOnly = state.isReadOnly;
            return Column(
              children: [
                if (state.isLoading)
                  const LinearProgressIndicator(color: AppTheme.primaryIndigo),
                StockTransferRouteHeader(
                  fromLabel: widget.isLoad
                      ? state.defaultWarehouse.name
                      : state.currentLocation.name,
                  toLabel: widget.isLoad
                      ? state.currentLocation.name
                      : state.defaultWarehouse.name,
                  dateLabel: _dateFormat.format(_issueDate),
                  isDark: isDark,
                  status: state.isEditingExisting ? state.status : null,
                ),
                if (!state.isLiveData)
                  const _Banner(
                    color: AppTheme.warningAmber,
                    text: 'Offline — showing last synced stock',
                  ),
                if (!state.isLoading && state.defaultWarehouse.id.isEmpty)
                  const _Banner(
                    color: AppTheme.errorRose,
                    text:
                        'Primary location is not configured in Zoho. '
                        'Contact your administrator — this transfer type is '
                        'disabled until this is fixed.',
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: state.rows.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.4,
                                  child: EmptyState(
                                    icon: Icons.inventory_2_outlined,
                                    title: widget.isLoad
                                        ? 'No items to plan'
                                        : 'No balance stock to unload',
                                    message: widget.isLoad
                                        ? 'Sync masters or tap "Add Item" below '
                                              'to plan today\'s issue to the van.'
                                        : 'There is no remaining van stock '
                                              'recorded for this location.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: state.rows.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final row = state.rows[index];
                                return StockTransferLineTile(
                                  row: row,
                                  onTap: readOnly
                                      ? null
                                      : () => _editRowQty(row),
                                  onRemove: readOnly
                                      ? null
                                      : () => context
                                            .read<StockTransferBloc>()
                                            .add(
                                              RemoveRow(row.item.id),
                                            ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextField(
                        controller: _notesController,
                        readOnly: readOnly,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ),
                EditorFooter(
                  rows: [
                    (
                      label: widget.isLoad
                          ? 'Total Quantity to Issue:'
                          : 'Total Quantity to Unload:',
                      value: formatQuantity(state.totalTransferQty),
                      emphasize: true,
                    ),
                  ],
                  buttonLabel: readOnly
                      ? 'VIEW ONLY — ${state.status.toUpperCase()}'
                      : state.isEditingExisting
                      ? 'UPDATE TRANSFER'
                      : widget.isLoad
                      ? 'ISSUE TO VAN'
                      : 'UNLOAD STOCK',
                  buttonColor: AppTheme.primaryIndigo,
                  onSave:
                      readOnly ||
                          state.isLoading ||
                          state.totalTransferQty <= 0 ||
                          state.defaultWarehouse.id.isEmpty
                      ? null
                      : () {
                          context.read<StockTransferBloc>().add(
                            SubmitTransfer(notes: _notesController.text),
                          );
                        },
                  trailing: widget.isLoad && !readOnly
                      ? SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openAddItemSheet,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Item'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryIndigo,
                              side: const BorderSide(
                                color: AppTheme.primaryIndigo,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final String text;

  const _Banner({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.12),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
