import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';

class ReportsTab extends StatelessWidget {
  final bool isDark;
  final VoidCallback onItemSalesReport;
  final VoidCallback onCustomerLedger;
  final VoidCallback onAgingReport;
  final VoidCallback onStockReport;

  const ReportsTab({
    super.key,
    required this.isDark,
    required this.onItemSalesReport,
    required this.onCustomerLedger,
    required this.onAgingReport,
    required this.onStockReport,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'REPORTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _ReportTile(
                title: 'Item Sales Report',
                subtitle: 'Itemwise quantities, amounts and customer reach.',
                icon: Icons.bar_chart_rounded,
                color: AppTheme.infoSky,
                isDark: isDark,
                onTap: onItemSalesReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Customer Ledger',
                subtitle: 'Statement of transactions and outstanding balance.',
                icon: Icons.account_balance_outlined,
                color: AppTheme.primaryIndigo,
                isDark: isDark,
                onTap: onCustomerLedger,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Agewise Receivables',
                subtitle:
                    'Outstanding by age: 0-15, 15-30, 30-60 and >60 days.',
                icon: Icons.hourglass_bottom_rounded,
                color: AppTheme.warningAmber,
                isDark: isDark,
                onTap: onAgingReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Stock Report',
                subtitle: 'Item stock and rates for your assigned location.',
                icon: Icons.inventory_2_outlined,
                color: AppTheme.successEmerald,
                isDark: isDark,
                onTap: onStockReport,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ReportTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}