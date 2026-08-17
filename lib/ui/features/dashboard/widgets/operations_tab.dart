import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../ui/core/extensions/l10n_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../cubit/list_layout_cubit.dart';
import 'list_grid_toggle.dart';
import 'van_action_tile.dart';

class OperationsTab extends StatelessWidget {
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
  final VoidCallback onCreateIssueToVan;
  final VoidCallback onCreateStockUnloading;

  /// True when the session salesperson has no van mapped — restricts stock-
  /// touching tiles; SO, Receipts, Expenses, Cash Closing, and Settings stay on.
  final bool ordersOnly;

  /// Fired instead of a tile's normal action when [ordersOnly] blocks it
  /// (e.g. shows a "Van not assigned" snackbar).
  final VoidCallback? onBlocked;

  const OperationsTab({
    super.key,
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
    required this.onCreateIssueToVan,
    required this.onCreateStockUnloading,
    this.ordersOnly = false,
    this.onBlocked,
  });

  List<_OpItem> _itemsFor(AppLocalizations l10n) => [
        _OpItem(
          title: l10n.salesInvoicesTitle,
          subtitle: l10n.salesInvoicesSubtitle,
          icon: Icons.description_outlined,
          color: AppTheme.primaryIndigo,
          onTap: onManageInvoices,
          onCreate: onCreateInvoice,
          createTooltip: l10n.newSalesInvoice,
        ),
        _OpItem(
          title: l10n.salesOrdersTitle,
          subtitle: l10n.salesOrdersSubtitle,
          icon: Icons.assignment_outlined,
          color: AppTheme.primaryIndigo,
          onTap: onManageOrders,
          onCreate: onCreateOrder,
          createTooltip: l10n.newSalesOrder,
          enabledInOrdersOnly: true,
        ),
        _OpItem(
          title: l10n.salesReturnsTitle,
          subtitle: l10n.salesReturnsSubtitle,
          icon: Icons.assignment_return_outlined,
          color: AppTheme.warningAmber,
          onTap: onManageReturns,
          onCreate: onCreateReturn,
          createTooltip: l10n.newSalesReturn,
        ),
        _OpItem(
          title: l10n.expensesTitle,
          subtitle: l10n.expensesSubtitle,
          icon: Icons.local_gas_station_outlined,
          color: AppTheme.errorRose,
          onTap: onManageExpenses,
          onCreate: onCreateExpense,
          createTooltip: l10n.newExpense,
          enabledInOrdersOnly: true,
        ),
        _OpItem(
          title: l10n.receiptsTitle,
          subtitle: l10n.receiptsSubtitle,
          icon: Icons.payments_outlined,
          color: AppTheme.successEmerald,
          onTap: onManageReceipts,
          onCreate: onCreateReceipt,
          createTooltip: l10n.newReceipt,
          enabledInOrdersOnly: true,
        ),
        _OpItem(
          title: l10n.issueToVanTitle,
          subtitle: l10n.issueToVanSubtitle,
          icon: Icons.local_shipping_outlined,
          color: AppTheme.primaryIndigo,
          onTap: onIssueToVan,
          onCreate: onCreateIssueToVan,
          createTooltip: l10n.newIssueToVan,
        ),
        _OpItem(
          title: l10n.stockUnloadingTitle,
          subtitle: l10n.stockUnloadingSubtitle,
          icon: Icons.unarchive_outlined,
          color: AppTheme.infoSky,
          onTap: onStockUnloading,
          onCreate: onCreateStockUnloading,
          createTooltip: l10n.newStockUnloading,
        ),
        _OpItem(
          title: l10n.dailyCashClosingTitle,
          subtitle: l10n.dailyCashClosingSubtitle,
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
        final items = _itemsFor(context.l10n);
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
                            childAspectRatio:
                                constraints.maxWidth >= 640 ? 1.05 : 0.88,
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
