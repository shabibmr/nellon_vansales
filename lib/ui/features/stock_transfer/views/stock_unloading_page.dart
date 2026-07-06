import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../../../domain/models/warehouse.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/utils/snackbars.dart';
import '../../../../ui/core/widgets/editor_footer.dart';
import '../../../../ui/core/widgets/empty_state.dart';
import '../bloc/stock_transfer_bloc.dart';

/// Stock-Unloading page: returns the van's balance stock from the current
/// location back to the organization's default warehouse at end-of-trip.
class StockUnloadingPage extends StatefulWidget {
  const StockUnloadingPage({super.key});

  @override
  State<StockUnloadingPage> createState() => _StockUnloadingPageState();
}

class _StockUnloadingPageState extends State<StockUnloadingPage> {
  final HiveDatabaseService _db = sl<HiveDatabaseService>();
  final TextEditingController _notesController = TextEditingController();
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void dispose() {
    _notesController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(StockTransferRow row) {
    final existing = _qtyControllers[row.item.id];
    if (existing != null) return existing;
    final created = TextEditingController(text: row.extraQty.toString());
    _qtyControllers[row.item.id] = created;
    return created;
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
      orElse: () =>
          Warehouse(id: id ?? '', name: 'Current Location', address: ''),
    );
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
      appBar: AppBar(title: const Text('Stock Unloading')),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSurface
                        : AppTheme.lightSurface,
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
                          currentLocation.name,
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
                          defaultWarehouse.name,
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
                ),
                Expanded(
                  child: state.rows.isEmpty
                      ? const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No balance stock to unload',
                          message:
                              'There is no remaining van stock recorded for '
                              'this location.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = state.rows[index];
                            return _UnloadRow(
                              row: row,
                              controller: _controllerFor(row),
                              isDark: isDark,
                              onChanged: (qty) {
                                context.read<StockTransferBloc>().add(
                                  UpdateExtraQty(
                                    itemId: row.item.id,
                                    quantity: qty,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                EditorFooter(
                  rows: [
                    (
                      label: 'Total Quantity to Unload:',
                      value: '${state.totalTransferQty}',
                      emphasize: true,
                    ),
                  ],
                  buttonLabel: 'UNLOAD STOCK',
                  buttonColor: AppTheme.primaryIndigo,
                  onSave: state.isLoading || state.totalTransferQty <= 0
                      ? null
                      : () {
                          context.read<StockTransferBloc>().add(
                            SubmitTransfer(notes: _notesController.text),
                          );
                        },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UnloadRow extends StatelessWidget {
  final StockTransferRow row;
  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<int> onChanged;

  const _UnloadRow({
    required this.row,
    required this.controller,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Van balance: ${row.currentStock}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Qty',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (val) => onChanged(int.tryParse(val) ?? 0),
            ),
          ),
        ],
      ),
    );
  }
}
