import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/repositories/salesperson_repository.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/theme/theme_cubit.dart';
import '../cubit/daily_stats_cubit.dart';
import '../cubit/daily_stats_state.dart';
import '../cubit/dashboard_nav_cubit.dart';
import 'analytics_reports_tab.dart';
import 'dashboard_app_bar.dart';
import 'dashboard_drawer.dart';
import 'dashboard_navigation_helpers.dart';
import 'dashboard_sidebar.dart';
import 'operations_tab.dart';
import 'reports_tab.dart';
import 'route_sequence_tab.dart';

class DashboardScaffold extends StatelessWidget {
  const DashboardScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeCubit>().state;
    final isDark = themeMode == AppThemeMode.dark;
    final isGlass = themeMode == AppThemeMode.glass;

    final (themeIcon, themeColor, themeTooltip) = switch (themeMode) {
      AppThemeMode.light => (
        Icons.dark_mode_outlined,
        AppTheme.primaryIndigo,
        'Switch to Dark',
      ),
      AppThemeMode.dark => (
        Icons.blur_on_rounded,
        Colors.amber,
        'Switch to Glass',
      ),
      AppThemeMode.glass => (
        Icons.light_mode_outlined,
        Colors.cyanAccent,
        'Switch to Light',
      ),
    };

    final statsCubit = context.read<DailyStatsCubit>();

    return BlocBuilder<DashboardNavCubit, int>(
      builder: (context, currentIndex) {
        return BlocBuilder<DailyStatsCubit, DailyStatsState>(
          builder: (context, statsState) {
            final tabs = [
              RouteSequenceTab(
                isDark: isDark || isGlass,
                onCustomerTap: (customer) => DashboardNavHelpers.showClientOperationsSheet(context, customer, isDark),
              ),
              AnalyticsReportsTab(
                isDark: isDark,
                isGlass: isGlass,
                todaySales: statsState.todaySales,
                todayPayments: statsState.todayPayments,
                todayExpenses: statsState.todayExpenses,
                todayReturns: statsState.todayReturns,
                todayOrdersTotal: statsState.todayOrdersTotal,
                completedDeliveries: statsState.completedDeliveries,
                last7DaysSales: statsState.last7DaysSales,
                onTapSales: () => DashboardNavHelpers.showSalesInvoiceListPage(context, statsCubit),
                onTapReceipts: () => DashboardNavHelpers.showReceiptListPage(context, statsCubit),
                onTapExpenses: () => DashboardNavHelpers.showExpenseListPage(context, statsCubit),
                onTapDeliveries: () => DashboardNavHelpers.showSalesInvoiceListPage(context, statsCubit),
                onTapOrders: () => DashboardNavHelpers.showSalesOrderListPage(context, statsCubit),
                onTapReturns: () => DashboardNavHelpers.showSalesReturnListPage(context, statsCubit),
              ),
              OperationsTab(
                ordersOnly: context.read<SalespersonRepository>().isOrdersOnlyMode,
                onBlocked: () => DashboardNavHelpers.blockIfOrdersOnly(context),
                onCashClosing: () => DashboardNavHelpers.showCashClosingForm(
                  context,
                  statsCubit,
                  statsState.todaySales,
                  statsState.todayPayments,
                  statsState.todayExpenses,
                ),
                onManageExpenses: () => DashboardNavHelpers.showExpenseListPage(context, statsCubit),
                onManageReceipts: () => DashboardNavHelpers.showReceiptListPage(context, statsCubit),
                onManageReturns: () => DashboardNavHelpers.showSalesReturnListPage(context, statsCubit),
                onManageInvoices: () => DashboardNavHelpers.showSalesInvoiceListPage(context, statsCubit),
                onManageOrders: () => DashboardNavHelpers.showSalesOrderListPage(context, statsCubit),
                onIssueToVan: () => DashboardNavHelpers.showIssueToVanListPage(context, statsCubit),
                onStockUnloading: () => DashboardNavHelpers.showStockUnloadingListPage(context, statsCubit),
                onCreateInvoice: () => DashboardNavHelpers.createNewInvoice(context, statsCubit),
                onCreateOrder: () => DashboardNavHelpers.createNewOrder(context, statsCubit),
                onCreateExpense: () => DashboardNavHelpers.createNewExpense(context, statsCubit),
                onCreateReceipt: () => DashboardNavHelpers.createNewReceipt(context, statsCubit),
                onCreateReturn: () => DashboardNavHelpers.createNewReturn(context, statsCubit),
                onCreateIssueToVan: () => DashboardNavHelpers.showIssueToVanPage(context, statsCubit),
                onCreateStockUnloading: () => DashboardNavHelpers.showStockUnloadingPage(context, statsCubit),
              ),
              ReportsTab(
                isDark: isDark,
                onItemSalesReport: () => DashboardNavHelpers.showItemSalesReport(context),
                onCustomerLedger: () => DashboardNavHelpers.showCustomerLedgerPage(context),
                onAgingReport: () => DashboardNavHelpers.showAgingReport(context),
                onStockReport: () => DashboardNavHelpers.showStockReport(context),
                onStockTransferHistoryReport: () => DashboardNavHelpers.showStockTransferHistoryReport(context),
                onTransactionsSummaryReport: () => DashboardNavHelpers.showTransactionsSummaryReport(context),
                onExpenseSummaryReport: () => DashboardNavHelpers.showExpenseSummaryReport(context),
                onInvoiceReceiptsSummaryReport: () => DashboardNavHelpers.showInvoiceReceiptsSummaryReport(context),
                onSalesSummaryByCustomerValueReport: () => DashboardNavHelpers.showSalesSummaryByCustomerValueReport(context),
                onSalesSummaryByCustomerItemReport: () => DashboardNavHelpers.showSalesSummaryByCustomerItemReport(context),
                onItemwiseOrdersSummaryReport: () => DashboardNavHelpers.showItemwiseOrdersSummaryReport(context),
                onOrdersSummaryByCustomerReport: () => DashboardNavHelpers.showOrdersSummaryByCustomerReport(context),
                onOrdersByShipmentDateReport: () => DashboardNavHelpers.showOrdersByShipmentDateReport(context),
                onOrdersReadyReport: () => DashboardNavHelpers.showOrdersReadyReport(context),
                onPendingOrdersReport: () => DashboardNavHelpers.showPendingOrdersReport(context),
                onOrdersInvoicedReport: () => DashboardNavHelpers.showOrdersInvoicedReport(context),
                onOrdersDelayedReport: () => DashboardNavHelpers.showOrdersDelayedReport(context),
                onItemwiseReturnsSummaryReport: () => DashboardNavHelpers.showItemwiseReturnsSummaryReport(context),
                onCustomerwiseReturnsSummaryReport: () => DashboardNavHelpers.showCustomerwiseReturnsSummaryReport(context),
              ),
            ];

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWideScreen = constraints.maxWidth > 800.0;

                return Scaffold(
                  drawer: isWideScreen
                      ? null
                      : DashboardDrawer(
                          isDark: isDark,
                          isGlass: isGlass,
                          themeIcon: themeIcon,
                          themeColor: themeColor,
                          themeTooltip: themeTooltip,
                        ),
                  appBar: DashboardAppBar(
                    currentIndex: currentIndex,
                    isWideScreen: isWideScreen,
                  ),
                  body: isWideScreen
                      ? Row(
                          children: [
                            DashboardSidebar(
                              currentIndex: currentIndex,
                              isDark: isDark,
                              isGlass: isGlass,
                              themeIcon: themeIcon,
                              themeColor: themeColor,
                              themeTooltip: themeTooltip,
                            ),
                            const VerticalDivider(width: 1, thickness: 1),
                            Expanded(
                              child: tabs[currentIndex],
                            ),
                          ],
                        )
                      : tabs[currentIndex],
                  bottomNavigationBar: isWideScreen
                      ? null
                      : Container(
                          decoration: BoxDecoration(
                            color: isGlass
                                ? AppTheme.glassBackground2
                                : (isDark ? AppTheme.darkBackground : AppTheme.lightSurface),
                            border: Border(
                              top: BorderSide(
                                color: isGlass
                                    ? AppTheme.glassBorder
                                    : (isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0)),
                                width: 1,
                              ),
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: BottomNavigationBar(
                              currentIndex: currentIndex <= 0
                                  ? 0
                                  : (currentIndex - 1).clamp(0, 2),
                              backgroundColor: Colors.transparent,
                              selectedItemColor: isGlass
                                  ? Colors.cyanAccent
                                  : AppTheme.primaryIndigo,
                              unselectedItemColor: isGlass
                                  ? AppTheme.glassTextSecondary
                                  : (isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary),
                              elevation: 0,
                              onTap: (index) => context
                                  .read<DashboardNavCubit>()
                                  .setTab(index + 1),
                              type: BottomNavigationBarType.fixed,
                              items: const [
                                BottomNavigationBarItem(
                                  icon: Icon(Icons.dashboard_outlined),
                                  activeIcon: Icon(Icons.dashboard),
                                  label: 'Dashboard',
                                ),
                                BottomNavigationBarItem(
                                  icon: Icon(Icons.receipt_long_outlined),
                                  activeIcon: Icon(Icons.receipt_long),
                                  label: 'Transactions',
                                ),
                                BottomNavigationBarItem(
                                  icon: Icon(Icons.assessment_outlined),
                                  activeIcon: Icon(Icons.assessment),
                                  label: 'Reports',
                                ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}
