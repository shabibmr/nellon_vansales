import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            VanActionTile(
              title: 'Sales Invoices',
              subtitle: 'View, filter, edit, or create offline sales invoices.',
              icon: Icons.description_outlined,
              color: AppTheme.primaryIndigo,
              isDark: isDark,
              onTap: onManageInvoices,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Sales Orders',
              subtitle: 'View, filter, edit, or create offline sales orders.',
              icon: Icons.assignment_outlined,
              color: AppTheme.primaryIndigo,
              isDark: isDark,
              onTap: onManageOrders,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Sales Returns',
              subtitle:
                  'View, filter, edit, or create credit notes for returned goods.',
              icon: Icons.assignment_return_outlined,
              color: AppTheme.warningAmber,
              isDark: isDark,
              onTap: onManageReturns,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Expenses',
              subtitle: 'View and log van trip expenses with receipt capture.',
              icon: Icons.local_gas_station_outlined,
              color: AppTheme.errorRose,
              isDark: isDark,
              onTap: onManageExpenses,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Receipts',
              subtitle: 'View and log customer payment receipt vouchers.',
              icon: Icons.payments_outlined,
              color: AppTheme.successEmerald,
              isDark: isDark,
              onTap: onManageReceipts,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Issue to Van',
              subtitle:
                  'Plan and load stock from the default warehouse onto the van.',
              icon: Icons.local_shipping_outlined,
              color: AppTheme.primaryIndigo,
              isDark: isDark,
              onTap: onIssueToVan,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Stock Unloading',
              subtitle:
                  'Return the van\'s balance stock back to the default warehouse.',
              icon: Icons.unarchive_outlined,
              color: AppTheme.infoSky,
              isDark: isDark,
              onTap: onStockUnloading,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Daily Cash Closing',
              subtitle:
                  'End of session cash count, inventory check & Zoho reconciliation.',
              icon: Icons.verified_outlined,
              color: AppTheme.infoSky,
              isDark: isDark,
              onTap: onCashClosing,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
