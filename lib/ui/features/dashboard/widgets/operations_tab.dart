import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../cubit/list_layout_cubit.dart';
import 'list_grid_toggle.dart';
import 'van_action_tile.dart';

class OperationsTab extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCashClosing;
  final VoidCallback onManageInvoices;
  final VoidCallback onManageOrders;
  final VoidCallback onManageExpenses;
  final VoidCallback onManageReceipts;
  final VoidCallback onManageReturns;
  final VoidCallback onIssueToVan;
  final VoidCallback onStockUnloading;

  /// Opens a blank new voucher editor (skips the list page).
  final VoidCallback onCreateInvoice;
  final VoidCallback onCreateOrder;
  final VoidCallback onCreateExpense;
  final VoidCallback onCreateReceipt;
  final VoidCallback onCreateReturn;

  /// True when the session salesperson has no van mapped — restricts stock-
  /// touching tiles; SO, Receipts, Expenses, Cash Closing, and Settings stay on.
  final bool ordersOnly;

  /// Fired instead of a tile's normal action when [ordersOnly] blocks it
  /// (e.g. shows a "Van not assigned" snackbar).
  final VoidCallback? onBlocked;

  const OperationsTab({
    super.key,
    required this.isDark,
    required this.onCashClosing,
    required this.onManageInvoices,
    required this.onManageOrders,
    required this.onManageExpenses,
    required this.onManageReceipts,
    required this.onManageReturns,
    required this.onIssueToVan,
    required this.onStockUnloading,
    required this.onCreateInvoice,
    required this.onCreateOrder,
    required this.onCreateExpense,
    required this.onCreateReceipt,
    required this.onCreateReturn,
    this.ordersOnly = false,
    this.onBlocked,
  });

  List<_OpItem> get _items => [
        _OpItem(
          title: 'Sales Invoices',
          subtitle: 'View, filter, edit, or create offline sales invoices.',
          icon: Icons.description_outlined,
          color: AppTheme.primaryIndigo,
          onTap: onManageInvoices,
          onCreate: onCreateInvoice,
          createTooltip: 'New Sales Invoice',
        ),
        _OpItem(
          title: 'Sales Orders',
          subtitle: 'View, filter, edit, or create offline sales orders.',
          icon: Icons.assignment_outlined,
          color: AppTheme.primaryIndigo,
          onTap: onManageOrders,
          onCreate: onCreateOrder,
          createTooltip: 'New Sales Order',
          enabledInOrdersOnly: true,
        ),
        _OpItem(
          title: 'Sales Returns',
          subtitle:
              'View, filter, edit, or create credit notes for returned goods.',
          icon: Icons.assignment_return_outlined,
          color: AppTheme.warningAmber,
          onTap: onManageReturns,
          onCreate: onCreateReturn,
          createTooltip: 'New Sales Return',
        ),
        _OpItem(
          title: 'Expenses',
          subtitle: 'View and log van trip expenses with receipt capture.',
          icon: Icons.local_gas_station_outlined,
          color: AppTheme.errorRose,
          onTap: onManageExpenses,
          onCreate: onCreateExpense,
          createTooltip: 'New Expense',
          enabledInOrdersOnly: true,
        ),
        _OpItem(
          title: 'Receipts',
          subtitle: 'View and log customer payment receipt vouchers.',
          icon: Icons.payments_outlined,
          color: AppTheme.successEmerald,
          onTap: onManageReceipts,
          onCreate: onCreateReceipt,
          createTooltip: 'New Receipt',
          enabledInOrdersOnly: true,
        ),
        _OpItem(
          title: 'Issue to Van',
          subtitle:
              'Plan and load stock from the default warehouse onto the van.',
          icon: Icons.local_shipping_outlined,
          color: AppTheme.primaryIndigo,
          onTap: onIssueToVan,
        ),
        _OpItem(
          title: 'Stock Unloading',
          subtitle:
              "Return the van's balance stock back to the default warehouse.",
          icon: Icons.unarchive_outlined,
          color: AppTheme.infoSky,
          onTap: onStockUnloading,
        ),
        _OpItem(
          title: 'Daily Cash Closing',
          subtitle:
              'End of session cash count, inventory check & Zoho reconciliation.',
          icon: Icons.verified_outlined,
          color: AppTheme.infoSky,
          onTap: onCashClosing,
          enabledInOrdersOnly: true,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ListLayoutCubit, bool>(
      builder: (context, isGrid) {
        final items = _items;
        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 640 ? 3 : 2;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isGrid ? 900 : 600),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: ListGridToggle(
                          isGrid: isGrid,
                          isDark: isDark,
                          onChanged: (value) =>
                              context.read<ListLayoutCubit>().setGrid(value),
                        ),
                      ),
                    ),
                    if (isGrid)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.95,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = items[index];
                              return _buildTile(item, isGrid: true);
                            },
                            childCount: items.length,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index.isOdd) {
                                return const SizedBox(height: 16);
                              }
                              final item = items[index ~/ 2];
                              return _buildTile(item);
                            },
                            childCount: items.length * 2 - 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTile(_OpItem item, {bool isGrid = false}) {
    final canCreate = item.onCreate != null;
    final blocked = ordersOnly && !item.enabledInOrdersOnly;
    return VanActionTile(
      title: item.title,
      subtitle: item.subtitle,
      icon: item.icon,
      color: item.color,
      isDark: isDark,
      onTap: item.onTap,
      isGrid: isGrid,
      actionIcon: canCreate ? Icons.add_rounded : Icons.arrow_forward_rounded,
      onActionTap: item.onCreate,
      actionTooltip: item.createTooltip,
      enabled: !blocked,
      onBlocked: onBlocked,
    );
  }
}

class _OpItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onCreate;
  final String? createTooltip;

  /// Whether this tile stays active when the session is orders-only
  /// (no van mapped). Defaults to false — stock-touching types stay blocked;
  /// SO / Receipts / Expenses / Cash Closing / Settings opt in.
  final bool enabledInOrdersOnly;

  const _OpItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.onCreate,
    this.createTooltip,
    this.enabledInOrdersOnly = false,
  });
}
