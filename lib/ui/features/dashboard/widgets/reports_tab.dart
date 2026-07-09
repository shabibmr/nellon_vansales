import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';

class ReportsTab extends StatelessWidget {
  final bool isDark;
  final VoidCallback onItemSalesReport;
  final VoidCallback onCustomerLedger;
  final VoidCallback onAgingReport;
  final VoidCallback onStockReport;

  final VoidCallback onTransactionsSummaryReport;
  final VoidCallback onExpenseSummaryReport;
  final VoidCallback onInvoiceReceiptsSummaryReport;
  final VoidCallback onSalesSummaryByCustomerValueReport;
  final VoidCallback onSalesSummaryByCustomerItemReport;

  final VoidCallback onItemwiseOrdersSummaryReport;
  final VoidCallback onOrdersSummaryByCustomerReport;
  final VoidCallback onOrdersReadyReport;
  final VoidCallback onPendingOrdersReport;
  final VoidCallback onOrdersInvoicedReport;
  final VoidCallback onOrdersDelayedReport;

  final VoidCallback onItemwiseReturnsSummaryReport;
  final VoidCallback onCustomerwiseReturnsSummaryReport;

  const ReportsTab({
    super.key,
    required this.isDark,
    required this.onItemSalesReport,
    required this.onCustomerLedger,
    required this.onAgingReport,
    required this.onStockReport,
    required this.onTransactionsSummaryReport,
    required this.onExpenseSummaryReport,
    required this.onInvoiceReceiptsSummaryReport,
    required this.onSalesSummaryByCustomerValueReport,
    required this.onSalesSummaryByCustomerItemReport,
    required this.onItemwiseOrdersSummaryReport,
    required this.onOrdersSummaryByCustomerReport,
    required this.onOrdersReadyReport,
    required this.onPendingOrdersReport,
    required this.onOrdersInvoicedReport,
    required this.onOrdersDelayedReport,
    required this.onItemwiseReturnsSummaryReport,
    required this.onCustomerwiseReturnsSummaryReport,
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

              Text(
                'TRANSACTIONS SUMMARY',
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
                title: 'Aggregate of All',
                subtitle: 'Invoices, receipts, expenses and returns by type.',
                icon: Icons.dashboard_outlined,
                color: AppTheme.primaryIndigo,
                isDark: isDark,
                onTap: onTransactionsSummaryReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Expense Summary',
                subtitle: 'Expense entries grouped by category.',
                icon: Icons.local_gas_station_outlined,
                color: AppTheme.errorRose,
                isDark: isDark,
                onTap: onExpenseSummaryReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Invoice Receipts Summary',
                subtitle: 'Receipts collected, grouped by payment mode.',
                icon: Icons.point_of_sale_outlined,
                color: AppTheme.successEmerald,
                isDark: isDark,
                onTap: onInvoiceReceiptsSummaryReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Sales Summary by Customer (Value)',
                subtitle: 'Invoice count and total value per customer.',
                icon: Icons.trending_up_rounded,
                color: AppTheme.infoSky,
                isDark: isDark,
                onTap: onSalesSummaryByCustomerValueReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Sales Summary by Customer (By Item)',
                subtitle: 'Itemwise sales breakdown per customer.',
                icon: Icons.shopping_bag_outlined,
                color: AppTheme.warningAmber,
                isDark: isDark,
                onTap: onSalesSummaryByCustomerItemReport,
              ),
              const SizedBox(height: 24),

              Text(
                'ORDERS',
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
                title: 'Itemwise Orders Summary',
                subtitle: 'Ordered quantities and amounts per item.',
                icon: Icons.bar_chart_rounded,
                color: AppTheme.infoSky,
                isDark: isDark,
                onTap: onItemwiseOrdersSummaryReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Orders Summary by Customer',
                subtitle: 'Order count and total value per customer.',
                icon: Icons.people_outline_rounded,
                color: AppTheme.primaryIndigo,
                isDark: isDark,
                onTap: onOrdersSummaryByCustomerReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Orders Ready',
                subtitle: 'Open orders due for shipment.',
                icon: Icons.local_shipping_outlined,
                color: AppTheme.successEmerald,
                isDark: isDark,
                onTap: onOrdersReadyReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Pending Orders',
                subtitle: 'Open orders not yet shipped or delayed.',
                icon: Icons.hourglass_empty_rounded,
                color: AppTheme.warningAmber,
                isDark: isDark,
                onTap: onPendingOrdersReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Orders Invoiced',
                subtitle: 'Orders already converted to an invoice.',
                icon: Icons.receipt_long_outlined,
                color: AppTheme.infoSky,
                isDark: isDark,
                onTap: onOrdersInvoicedReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Orders Delayed',
                subtitle: 'Open orders past their shipment date.',
                icon: Icons.warning_amber_rounded,
                color: AppTheme.errorRose,
                isDark: isDark,
                onTap: onOrdersDelayedReport,
              ),
              const SizedBox(height: 24),

              Text(
                'SALES RETURNS',
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
                title: 'Itemwise Summary',
                subtitle: 'Returned quantities and refunds per item.',
                icon: Icons.assignment_return_outlined,
                color: AppTheme.warningAmber,
                isDark: isDark,
                onTap: onItemwiseReturnsSummaryReport,
              ),
              const SizedBox(height: 10),
              _ReportTile(
                title: 'Customerwise Summary',
                subtitle: 'Return count and refunds per customer.',
                icon: Icons.people_outline_rounded,
                color: AppTheme.errorRose,
                isDark: isDark,
                onTap: onCustomerwiseReturnsSummaryReport,
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