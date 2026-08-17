import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../cubit/list_layout_cubit.dart';
import 'list_grid_toggle.dart';
import 'van_action_tile.dart';

class ReportsTab extends StatelessWidget {
  final bool isDark;
  final VoidCallback onItemSalesReport;
  final VoidCallback onCustomerLedger;
  final VoidCallback onAgingReport;
  final VoidCallback onStockReport;
  final VoidCallback onStockTransferHistoryReport;

  final VoidCallback onTransactionsSummaryReport;
  final VoidCallback onExpenseSummaryReport;
  final VoidCallback onInvoiceReceiptsSummaryReport;
  final VoidCallback onSalesSummaryByCustomerValueReport;
  final VoidCallback onSalesSummaryByCustomerItemReport;

  final VoidCallback onItemwiseOrdersSummaryReport;
  final VoidCallback onOrdersSummaryByCustomerReport;
  final VoidCallback onOrdersByShipmentDateReport;
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
    required this.onStockTransferHistoryReport,
    required this.onTransactionsSummaryReport,
    required this.onExpenseSummaryReport,
    required this.onInvoiceReceiptsSummaryReport,
    required this.onSalesSummaryByCustomerValueReport,
    required this.onSalesSummaryByCustomerItemReport,
    required this.onItemwiseOrdersSummaryReport,
    required this.onOrdersSummaryByCustomerReport,
    required this.onOrdersByShipmentDateReport,
    required this.onOrdersReadyReport,
    required this.onPendingOrdersReport,
    required this.onOrdersInvoicedReport,
    required this.onOrdersDelayedReport,
    required this.onItemwiseReturnsSummaryReport,
    required this.onCustomerwiseReturnsSummaryReport,
  });

  List<_ReportSection> get _sections => [
        _ReportSection(
          title: 'REPORTS',
          items: [
            _ReportItem(
              title: 'Item Sales Report',
              subtitle: 'Itemwise quantities, amounts and customer reach.',
              icon: Icons.bar_chart_rounded,
              color: AppTheme.infoSky,
              onTap: onItemSalesReport,
            ),
            _ReportItem(
              title: 'Customer Ledger',
              subtitle: 'Statement of transactions and outstanding balance.',
              icon: Icons.account_balance_outlined,
              color: AppTheme.primaryIndigo,
              onTap: onCustomerLedger,
            ),
            _ReportItem(
              title: 'Agewise Receivables',
              subtitle:
                  'Outstanding by age: 0-15, 15-30, 30-60 and >60 days.',
              icon: Icons.hourglass_bottom_rounded,
              color: AppTheme.warningAmber,
              onTap: onAgingReport,
            ),
            _ReportItem(
              title: 'Stock Report',
              subtitle: 'Item stock and rates for your assigned location.',
              icon: Icons.inventory_2_outlined,
              color: AppTheme.successEmerald,
              onTap: onStockReport,
            ),
            _ReportItem(
              title: 'Stock Transfer History',
              subtitle: 'Issue to Van and Stock Unloading vouchers.',
              icon: Icons.local_shipping_outlined,
              color: AppTheme.primaryIndigo,
              onTap: onStockTransferHistoryReport,
            ),
          ],
        ),
        _ReportSection(
          title: 'TRANSACTIONS SUMMARY',
          items: [
            _ReportItem(
              title: 'Aggregate of All',
              subtitle: 'Invoices, receipts, expenses and returns by type.',
              icon: Icons.dashboard_outlined,
              color: AppTheme.primaryIndigo,
              onTap: onTransactionsSummaryReport,
            ),
            _ReportItem(
              title: 'Expense Summary',
              subtitle: 'Expense entries grouped by category.',
              icon: Icons.local_gas_station_outlined,
              color: AppTheme.errorRose,
              onTap: onExpenseSummaryReport,
            ),
            _ReportItem(
              title: 'Invoice Receipts Summary',
              subtitle: 'Receipts collected, grouped by payment mode.',
              icon: Icons.point_of_sale_outlined,
              color: AppTheme.successEmerald,
              onTap: onInvoiceReceiptsSummaryReport,
            ),
            _ReportItem(
              title: 'Sales Summary by Customer (Value)',
              subtitle: 'Invoice count and total value per customer.',
              icon: Icons.trending_up_rounded,
              color: AppTheme.infoSky,
              onTap: onSalesSummaryByCustomerValueReport,
            ),
            _ReportItem(
              title: 'Sales Summary by Customer (By Item)',
              subtitle: 'Itemwise sales breakdown per customer.',
              icon: Icons.shopping_bag_outlined,
              color: AppTheme.warningAmber,
              onTap: onSalesSummaryByCustomerItemReport,
            ),
          ],
        ),
        _ReportSection(
          title: 'ORDERS',
          items: [
            _ReportItem(
              title: 'Itemwise Orders Summary',
              subtitle: 'Ordered quantities and amounts per item.',
              icon: Icons.bar_chart_rounded,
              color: AppTheme.infoSky,
              onTap: onItemwiseOrdersSummaryReport,
            ),
            _ReportItem(
              title: 'Orders Summary by Customer',
              subtitle: 'Order count and total value per customer.',
              icon: Icons.people_outline_rounded,
              color: AppTheme.primaryIndigo,
              onTap: onOrdersSummaryByCustomerReport,
            ),
            _ReportItem(
              title: 'Orders by Shipment Date',
              subtitle:
                  'Filter by ship date, convert to invoice, plan stock.',
              icon: Icons.event_available_rounded,
              color: AppTheme.primaryIndigo,
              onTap: onOrdersByShipmentDateReport,
            ),
            _ReportItem(
              title: 'Orders Ready',
              subtitle: 'Open orders due for shipment.',
              icon: Icons.local_shipping_outlined,
              color: AppTheme.successEmerald,
              onTap: onOrdersReadyReport,
            ),
            _ReportItem(
              title: 'Pending Orders',
              subtitle: 'Open orders not yet shipped or delayed.',
              icon: Icons.hourglass_empty_rounded,
              color: AppTheme.warningAmber,
              onTap: onPendingOrdersReport,
            ),
            _ReportItem(
              title: 'Orders Invoiced',
              subtitle: 'Orders already converted to an invoice.',
              icon: Icons.receipt_long_outlined,
              color: AppTheme.infoSky,
              onTap: onOrdersInvoicedReport,
            ),
            _ReportItem(
              title: 'Orders Delayed',
              subtitle: 'Open orders past their shipment date.',
              icon: Icons.warning_amber_rounded,
              color: AppTheme.errorRose,
              onTap: onOrdersDelayedReport,
            ),
          ],
        ),
        _ReportSection(
          title: 'SALES RETURNS',
          items: [
            _ReportItem(
              title: 'Itemwise Summary',
              subtitle: 'Returned quantities and refunds per item.',
              icon: Icons.assignment_return_outlined,
              color: AppTheme.warningAmber,
              onTap: onItemwiseReturnsSummaryReport,
            ),
            _ReportItem(
              title: 'Customerwise Summary',
              subtitle: 'Return count and refunds per customer.',
              icon: Icons.people_outline_rounded,
              color: AppTheme.errorRose,
              onTap: onCustomerwiseReturnsSummaryReport,
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ListLayoutCubit, bool>(
      builder: (context, isGrid) {
        final sections = _sections;
        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 640 ? 3 : 2;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isGrid ? 900 : 700),
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
                    for (var s = 0; s < sections.length; s++) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            s == 0 ? 16 : 24,
                            20,
                            12,
                          ),
                          child: Text(
                            sections[s].title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ),
                      ),
                      if (isGrid)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            s == sections.length - 1 ? 24 : 0,
                          ),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio:
                                  constraints.maxWidth >= 640 ? 1.05 : 0.88,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = sections[s].items[index];
                                return VanActionTile(
                                  title: item.title,
                                  subtitle: item.subtitle,
                                  icon: item.icon,
                                  color: item.color,
                                 
                                  onTap: item.onTap,
                                  isGrid: true,
                                );
                              },
                              childCount: sections[s].items.length,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            s == sections.length - 1 ? 24 : 0,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final items = sections[s].items;
                                if (index.isOdd) {
                                  return const SizedBox(height: 10);
                                }
                                final item = items[index ~/ 2];
                                return VanActionTile(
                                  title: item.title,
                                  subtitle: item.subtitle,
                                  icon: item.icon,
                                  color: item.color,
                                 
                                  onTap: item.onTap,
                                );
                              },
                              childCount: sections[s].items.length * 2 - 1,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReportSection {
  final String title;
  final List<_ReportItem> items;

  const _ReportSection({required this.title, required this.items});
}

class _ReportItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ReportItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

