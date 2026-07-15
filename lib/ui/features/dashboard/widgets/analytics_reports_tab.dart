import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/salesperson.dart';
import '../../../../ui/core/cubit/salesperson_cubit.dart';
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

  const AnalyticsReportsTab({
    super.key,
    required this.isDark,
    this.isGlass = false,
    required this.todaySales,
    required this.todayPayments,
    required this.todayExpenses,
    required this.todayReturns,
    required this.completedDeliveries,
  });

  static String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

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
              BlocBuilder<SalespersonCubit, Salesperson?>(
                builder: (context, salesperson) {
                  final name = salesperson?.name.trim();
                  final greeting = _timeGreeting();
                  final title = (name != null && name.isNotEmpty)
                      ? '$greeting, $name'
                      : greeting;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isGlass
                                ? Colors.white
                                : (isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Here's today's van performance.",
                          style: TextStyle(
                            fontSize: 13,
                            color: isGlass
                                ? AppTheme.glassTextSecondary
                                : (isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
              _ReturnsCard(cs: cs, todayReturns: todayReturns, isDark: isDark),
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
            child: const Icon(
              Icons.assignment_return_outlined,
              color: AppTheme.warningAmber,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Sales Returns',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
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
