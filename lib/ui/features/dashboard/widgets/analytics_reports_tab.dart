import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import 'van_metric_card.dart';

class AnalyticsReportsTab extends StatelessWidget {
  final bool isDark;
  final bool isGlass;
  final double todaySales;
  final double todayPayments;
  final double todayExpenses;
  final double todayReturns;
  final int completedDeliveries;
  final VoidCallback onItemSalesReport;
  final VoidCallback onCustomerLedger;
  final VoidCallback onAgingReport;

  const AnalyticsReportsTab({
    super.key,
    required this.isDark,
    this.isGlass = false,
    required this.todaySales,
    required this.todayPayments,
    required this.todayExpenses,
    required this.todayReturns,
    required this.completedDeliveries,
    required this.onItemSalesReport,
    required this.onCustomerLedger,
    required this.onAgingReport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.org.currencySymbol;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Metric cards ──────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: VanMetricCard(
                      title: 'Today Sales',
                      value: '$cs${todaySales.toStringAsFixed(2)}',
                      icon: Icons.point_of_sale_rounded,
                      color: AppTheme.primaryIndigo,
                      isDark: isDark,
                      isGlass: isGlass,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VanMetricCard(
                      title: 'Collections',
                      value: '$cs${todayPayments.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppTheme.successEmerald,
                      isDark: isDark,
                      isGlass: isGlass,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: VanMetricCard(
                      title: 'Expenses',
                      value: '$cs${todayExpenses.toStringAsFixed(2)}',
                      icon: Icons.receipt_long_rounded,
                      color: AppTheme.errorRose,
                      isDark: isDark,
                      isGlass: isGlass,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VanMetricCard(
                      title: 'Deliveries Done',
                      value: '$completedDeliveries Clients',
                      icon: Icons.verified_user_rounded,
                      color: AppTheme.infoSky,
                      isDark: isDark,
                      isGlass: isGlass,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Sales Returns — full-width card
              _ReturnsCard(
                cs: cs,
                todayReturns: todayReturns,
                isDark: isDark,
              ),

              const SizedBox(height: 28),

              // ── Reports section ───────────────────────────
              Text(
                'REPORTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
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
                subtitle: 'Outstanding by age: 0-15, 15-30, 30-60 and >60 days.',
                icon: Icons.hourglass_bottom_rounded,
                color: AppTheme.warningAmber,
                isDark: isDark,
                onTap: onAgingReport,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Full-width Sales Returns highlight card ────────────────────────────────

class _ReturnsCard extends StatelessWidget {
  final String cs;
  final double todayReturns;
  final bool isDark;

  const _ReturnsCard({
    required this.cs,
    required this.todayReturns,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warningAmber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.assignment_return_outlined, color: AppTheme.warningAmber, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Sales Returns',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$cs${todayReturns.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.warningAmber,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Compact report navigation tile ────────────────────────────────────────

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
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      )),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
          ],
        ),
      ),
    );
  }
}
