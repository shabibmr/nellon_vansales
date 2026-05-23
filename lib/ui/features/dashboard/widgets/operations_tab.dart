import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';
import 'van_action_tile.dart';

class OperationsTab extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCreateCustomer;
  final VoidCallback onLogExpense;
  final VoidCallback onCashClosing;
  final VoidCallback onSwitchRoute;

  const OperationsTab({
    super.key,
    required this.isDark,
    required this.onCreateCustomer,
    required this.onLogExpense,
    required this.onCashClosing,
    required this.onSwitchRoute,
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
              title: 'Register New Customer',
              subtitle: 'Create customer details offline. Enqueues instantly to Zoho.',
              icon: Icons.person_add_alt_outlined,
              color: AppTheme.primaryIndigo,
              isDark: isDark,
              onTap: onCreateCustomer,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Log Van Expense',
              subtitle: 'Log operations costs (fuel, food, tolls) with receipt capture.',
              icon: Icons.local_gas_station_outlined,
              color: AppTheme.errorRose,
              isDark: isDark,
              onTap: onLogExpense,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Daily Cash Closing',
              subtitle: 'End of session cash count, inventory check & Zoho reconciliation.',
              icon: Icons.verified_outlined,
              color: AppTheme.successEmerald,
              isDark: isDark,
              onTap: onCashClosing,
            ),
            const SizedBox(height: 16),
            VanActionTile(
              title: 'Switch Selected Route',
              subtitle: 'Choose a different active sequence route list.',
              icon: Icons.alt_route_rounded,
              color: AppTheme.infoSky,
              isDark: isDark,
              onTap: onSwitchRoute,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
