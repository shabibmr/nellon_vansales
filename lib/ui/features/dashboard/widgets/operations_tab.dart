import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';
import 'van_action_tile.dart';

class OperationsTab extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCreateCustomer;
  final VoidCallback onCashClosing;
  final VoidCallback onManageInvoices;
  final VoidCallback onManageExpenses;
  final VoidCallback onManageReceipts;
  final VoidCallback onManageReturns;
  final VoidCallback onSyncMasters;

  const OperationsTab({
    super.key,
    required this.isDark,
    required this.onCreateCustomer,
    required this.onCashClosing,
    required this.onManageInvoices,
    required this.onManageExpenses,
    required this.onManageReceipts,
    required this.onManageReturns,
    required this.onSyncMasters,
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
              title: 'Manage Sales Invoices',
              subtitle: 'View, filter, edit, or create offline sales invoices.',
              icon: Icons.description_outlined,
              color: AppTheme.primaryIndigo,
              isDark: isDark,
              onTap: onManageInvoices,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Manage Sales Returns',
              subtitle: 'View, filter, edit, or create credit notes for returned goods.',
              icon: Icons.assignment_return_outlined,
              color: AppTheme.warningAmber,
              isDark: isDark,
              onTap: onManageReturns,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Manage Expenses',
              subtitle: 'View and log van trip expenses with receipt capture.',
              icon: Icons.local_gas_station_outlined,
              color: AppTheme.errorRose,
              isDark: isDark,
              onTap: onManageExpenses,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Manage Receipts',
              subtitle: 'View and log customer payment receipt vouchers.',
              icon: Icons.payments_outlined,
              color: AppTheme.successEmerald,
              isDark: isDark,
              onTap: onManageReceipts,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Register New Customer',
              subtitle: 'Create customer details offline. Enqueues instantly to Zoho.',
              icon: Icons.person_add_alt_outlined,
              color: AppTheme.primaryIndigo,
              isDark: isDark,
              onTap: onCreateCustomer,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Sync Master Data',
              subtitle: 'Refresh customers, items, taxes and org data from Zoho Books.',
              icon: Icons.cloud_sync_outlined,
              color: AppTheme.infoSky,
              isDark: isDark,
              onTap: onSyncMasters,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Daily Cash Closing',
              subtitle: 'End of session cash count, inventory check & Zoho reconciliation.',
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
