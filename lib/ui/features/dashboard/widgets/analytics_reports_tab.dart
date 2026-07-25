import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/salesperson.dart';
import '../../../../ui/core/cubit/salesperson_cubit.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../cubit/daily_stats_state.dart';
import 'van_metric_card.dart';
import 'sales_trend_chart.dart';

class AnalyticsReportsTab extends StatelessWidget {
  final bool isDark;
  final bool isGlass;
  final double todaySales;
  final double todayPayments;
  final double todayExpenses;
  final double todayReturns;
  final double todayOrdersTotal;
  final int completedDeliveries;
  final List<DailySalesPoint> last7DaysSales;
  final VoidCallback onTapSales;
  final VoidCallback onTapReceipts;
  final VoidCallback onTapExpenses;
  final VoidCallback onTapDeliveries;
  final VoidCallback onTapOrders;
  final VoidCallback onTapReturns;

  const AnalyticsReportsTab({
    super.key,
    required this.isDark,
    this.isGlass = false,
    required this.todaySales,
    required this.todayPayments,
    required this.todayExpenses,
    required this.todayReturns,
    required this.todayOrdersTotal,
    required this.completedDeliveries,
    required this.last7DaysSales,
    required this.onTapSales,
    required this.onTapReceipts,
    required this.onTapExpenses,
    required this.onTapDeliveries,
    required this.onTapOrders,
    required this.onTapReturns,
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
                      onTap: onTapSales,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VanMetricCard(
                      title: 'Receipts',
                      value: '$cs${todayPayments.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppTheme.successEmerald,
                      isDark: isDark,
                      isGlass: isGlass,
                      onTap: onTapReceipts,
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
                      onTap: onTapExpenses,
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
                      onTap: onTapDeliveries,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: VanMetricCard(
                      title: 'Orders Total',
                      value: '$cs${todayOrdersTotal.toStringAsFixed(2)}',
                      icon: Icons.assignment_turned_in_outlined,
                      color: AppTheme.primaryIndigo,
                      isDark: isDark,
                      isGlass: isGlass,
                      onTap: onTapOrders,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: VanMetricCard(
                      title: 'Sales Returns',
                      value: '$cs${todayReturns.toStringAsFixed(2)}',
                      icon: Icons.assignment_return_outlined,
                      color: AppTheme.warningAmber,
                      isDark: isDark,
                      isGlass: isGlass,
                      onTap: onTapReturns,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SalesTrendChart(
                points: last7DaysSales,
                isDark: isDark,
                isGlass: isGlass,
                currencySymbol: cs,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
