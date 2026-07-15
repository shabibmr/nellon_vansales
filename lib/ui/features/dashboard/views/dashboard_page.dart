import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/theme/theme_cubit.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../sync/bloc/sync_bloc.dart';
import '../../expenses/bloc/expense_bloc.dart';
import '../../expenses/views/expense_list_page.dart';
import '../../receipts/bloc/receipt_bloc.dart';
import '../../receipts/views/receipt_list_page.dart';
import '../widgets/route_sequence_tab.dart';
import '../widgets/analytics_reports_tab.dart';
import '../widgets/reports_tab.dart';
import '../widgets/operations_tab.dart';
import '../widgets/global_search_sheet.dart';
import '../widgets/item_details_dialog.dart';
import '../widgets/client_operations_sheet.dart';
import '../widgets/invoice_flow_sheet.dart';
import '../widgets/receipt_payment_dialog.dart';
import '../widgets/sales_return_dialog.dart';
import '../widgets/cash_closing_dialog.dart';
import '../../sales_invoice/views/sales_invoice_list_page.dart';
import '../../sales_order/views/sales_order_list_page.dart';
import '../../sales_order/bloc/sales_order_bloc.dart';
import '../../sales_order/views/sales_order_editor_page.dart';
import '../../sales_return/bloc/sales_return_bloc.dart';
import '../../sales_return/views/sales_return_list_page.dart';
import '../../stock_transfer/bloc/stock_transfer_bloc.dart';
import '../../stock_transfer/views/issue_to_van_page.dart';
import '../../stock_transfer/views/stock_unloading_page.dart';
import '../../reports/views/item_sales_report_page.dart';
import '../../reports/views/aging_receivables_report_page.dart';
import '../../reports/views/stock_report_page.dart';
import '../../reports/views/transactions_summary_report_page.dart';
import '../../reports/views/expense_summary_report_page.dart';
import '../../reports/views/invoice_receipts_summary_report_page.dart';
import '../../reports/views/sales_summary_by_customer_value_report_page.dart';
import '../../reports/views/sales_summary_by_customer_item_report_page.dart';
import '../../reports/views/itemwise_orders_summary_report_page.dart';
import '../../reports/views/orders_summary_by_customer_report_page.dart';
import '../../reports/views/order_status_report_page.dart';
import '../../reports/views/itemwise_returns_summary_report_page.dart';
import '../../reports/views/customerwise_returns_summary_report_page.dart';
import '../../ledger/bloc/customer_ledger_bloc.dart';
import '../../ledger/views/customer_ledger_page.dart';
import '../../sync/views/masters_sync_page.dart';
import '../../licensing/widgets/mock_live_switch_tile.dart';
import '../../../core/extensions/org_context_extension.dart';
import '../cubit/dashboard_nav_cubit.dart';
import '../cubit/daily_stats_cubit.dart';
import '../cubit/daily_stats_state.dart';

/// The central workspace of the Van Sales application.
///
/// Features a BLoC-driven multi-tab view (route sequence, dashboard, operations, and reports)
/// displaying real-time daily sales, collections, route stats, and triggers to create new entities.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<DashboardNavCubit>(
          create: (_) => DashboardNavCubit(),
        ),
        BlocProvider<DailyStatsCubit>(
          create: (_) => DailyStatsCubit(dbService: sl<HiveDatabaseService>()),
        ),
      ],
      child: const _DashboardPageView(),
    );
  }
}

class _DashboardPageView extends StatelessWidget {
  const _DashboardPageView();

  void _showGlobalSearchSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return GlobalSearchSheet(
          isDark: isDark,
          onCustomerSelected: (customer) {
            Navigator.pop(sheetCtx); // Close search
            _showClientOperationsSheet(context, customer, isDark); // Open customer actions sheet!
          },
          onItemSelected: (item) {
            Navigator.pop(sheetCtx); // Close search
            _showItemDetailsDialog(context, item, isDark); // Open quick details dialog
          },
        );
      },
    );
  }

  void _showItemDetailsDialog(BuildContext context, Item item, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => ItemDetailsDialog(item: item),
    );
  }

  void _showClientOperationsSheet(BuildContext context, Customer customer, bool isDark) {
    final dailyStatsCubit = context.read<DailyStatsCubit>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return ClientOperationsSheet(
          customer: customer,
          isDark: isDark,
          onNewInvoiceTap: () {
            Navigator.pop(sheetCtx);
            _launchInvoiceFlow(context, dailyStatsCubit, customer, isDark);
          },
          onNewOrderTap: () {
            Navigator.pop(sheetCtx);
            _launchSalesOrderFlow(context, dailyStatsCubit, customer);
          },
          onReceiptPaymentTap: () {
            Navigator.pop(sheetCtx);
            _launchPaymentFlow(context, dailyStatsCubit, customer, isDark);
          },
          onSalesReturnTap: () {
            Navigator.pop(sheetCtx);
            _launchSalesReturnFlow(context, dailyStatsCubit, customer, isDark);
          },
        );
      },
    );
  }

  void _launchSalesOrderFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer) {
    final bloc = context.read<SalesOrderBloc>();
    bloc.add(StartNewOrder());
    bloc.add(UpdateOrderCustomer(customer));

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SalesOrderEditorPage()),
    ).then((_) {
      statsCubit.refresh();
    });
  }

  void _launchInvoiceFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return InvoiceFlowSheet(
          customer: customer,
          isDark: isDark,
          onInvoiceSubmitted: () {
            statsCubit.refresh();
          },
        );
      },
    );
  }

  void _launchPaymentFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => ReceiptPaymentDialog(
        customer: customer,
        onPaymentLogged: () {
          statsCubit.refresh();
        },
      ),
    );
  }

  void _launchSalesReturnFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => SalesReturnDialog(
        customer: customer,
        onReturnConfirmed: () {
          statsCubit.refresh();
        },
      ),
    );
  }

  void _showItemSalesReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ItemSalesReportPage()),
    );
  }

  void _showAgingReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgingReceivablesReportPage()),
    );
  }

  void _showStockReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockReportPage()),
    );
  }

  void _showTransactionsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionsSummaryReportPage()),
    );
  }

  void _showExpenseSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseSummaryReportPage()),
    );
  }

  void _showInvoiceReceiptsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InvoiceReceiptsSummaryReportPage(),
      ),
    );
  }

  void _showSalesSummaryByCustomerValueReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SalesSummaryByCustomerValueReportPage(),
      ),
    );
  }

  void _showSalesSummaryByCustomerItemReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SalesSummaryByCustomerItemReportPage(),
      ),
    );
  }

  void _showItemwiseOrdersSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemwiseOrdersSummaryReportPage(),
      ),
    );
  }

  void _showOrdersSummaryByCustomerReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrdersSummaryByCustomerReportPage(),
      ),
    );
  }

  void _showOrdersReadyReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrderStatusReportPage(
          filter: OrderStatusFilter.readyOrPending,
          title: 'Orders Ready',
        ),
      ),
    );
  }

  void _showPendingOrdersReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrderStatusReportPage(
          filter: OrderStatusFilter.readyOrPending,
          title: 'Pending Orders',
        ),
      ),
    );
  }

  void _showOrdersInvoicedReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrderStatusReportPage(
          filter: OrderStatusFilter.invoiced,
          title: 'Orders Invoiced',
        ),
      ),
    );
  }

  void _showOrdersDelayedReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrderStatusReportPage(
          filter: OrderStatusFilter.delayed,
          title: 'Orders Delayed',
        ),
      ),
    );
  }

  void _showItemwiseReturnsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemwiseReturnsSummaryReportPage(),
      ),
    );
  }

  void _showCustomerwiseReturnsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerwiseReturnsSummaryReportPage(),
      ),
    );
  }

  void _showSalesReturnListPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<SalesReturnBloc>().add(LoadReturns());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SalesReturnListPage()),
    ).then((_) => statsCubit.refresh());
  }

  void _showExpenseListPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<ExpenseBloc>().add(LoadExpenses());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseListPage()),
    ).then((_) => statsCubit.refresh());
  }

  void _showReceiptListPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<ReceiptBloc>().add(LoadReceipts());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReceiptListPage()),
    ).then((_) => statsCubit.refresh());
  }

  void _showCustomerLedgerPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<CustomerLedgerBloc>(),
          child: const CustomerLedgerPage(),
        ),
      ),
    );
  }

  void _showMastersSyncPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MastersSyncPage()),
    );
  }

  void _showIssueToVanPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<StockTransferBloc>().add(LoadIssueGrid());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IssueToVanPage()),
    ).then((_) => statsCubit.refresh());
  }

  void _showStockUnloadingPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<StockTransferBloc>().add(LoadUnloadGrid());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockUnloadingPage()),
    ).then((_) => statsCubit.refresh());
  }

  void _showCashClosingForm(BuildContext context, DailyStatsCubit statsCubit, double todaySales, double todayPayments, double todayExpenses) {
    showDialog(
      context: context,
      builder: (context) => CashClosingDialog(
        todaySales: todaySales,
        todayPayments: todayPayments,
        todayExpenses: todayExpenses,
        onSessionReconciled: () {
          statsCubit.refresh();
        },
      ),
    );
  }

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
                onCustomerTap: (customer) => _showClientOperationsSheet(context, customer, isDark),
              ),
              AnalyticsReportsTab(
                isDark: isDark,
                isGlass: isGlass,
                todaySales: statsState.todaySales,
                todayPayments: statsState.todayPayments,
                todayExpenses: statsState.todayExpenses,
                todayReturns: statsState.todayReturns,
                completedDeliveries: statsState.completedDeliveries,
              ),
              OperationsTab(
                isDark: isDark || isGlass,
                onCashClosing: () => _showCashClosingForm(
                  context,
                  statsCubit,
                  statsState.todaySales,
                  statsState.todayPayments,
                  statsState.todayExpenses,
                ),
                onManageExpenses: () => _showExpenseListPage(context, statsCubit),
                onManageReceipts: () => _showReceiptListPage(context, statsCubit),
                onManageReturns: () => _showSalesReturnListPage(context, statsCubit),
                onManageInvoices: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SalesInvoiceListPage(),
                    ),
                  ).then((_) {
                    statsCubit.refresh();
                  });
                },
                onManageOrders: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SalesOrderListPage()),
                  ).then((_) {
                    statsCubit.refresh();
                  });
                },
                onIssueToVan: () => _showIssueToVanPage(context, statsCubit),
                onStockUnloading: () => _showStockUnloadingPage(context, statsCubit),
              ),
              ReportsTab(
                isDark: isDark,
                onItemSalesReport: () => _showItemSalesReport(context),
                onCustomerLedger: () => _showCustomerLedgerPage(context),
                onAgingReport: () => _showAgingReport(context),
                onStockReport: () => _showStockReport(context),
                onTransactionsSummaryReport: () => _showTransactionsSummaryReport(context),
                onExpenseSummaryReport: () => _showExpenseSummaryReport(context),
                onInvoiceReceiptsSummaryReport: () => _showInvoiceReceiptsSummaryReport(context),
                onSalesSummaryByCustomerValueReport: () => _showSalesSummaryByCustomerValueReport(context),
                onSalesSummaryByCustomerItemReport: () => _showSalesSummaryByCustomerItemReport(context),
                onItemwiseOrdersSummaryReport: () => _showItemwiseOrdersSummaryReport(context),
                onOrdersSummaryByCustomerReport: () => _showOrdersSummaryByCustomerReport(context),
                onOrdersReadyReport: () => _showOrdersReadyReport(context),
                onPendingOrdersReport: () => _showPendingOrdersReport(context),
                onOrdersInvoicedReport: () => _showOrdersInvoicedReport(context),
                onOrdersDelayedReport: () => _showOrdersDelayedReport(context),
                onItemwiseReturnsSummaryReport: () => _showItemwiseReturnsSummaryReport(context),
                onCustomerwiseReturnsSummaryReport: () => _showCustomerwiseReturnsSummaryReport(context),
              ),
            ];

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWideScreen = constraints.maxWidth > 800.0;

                return Scaffold(
                  drawer: isWideScreen
                      ? null
                      : Drawer(
                          backgroundColor: isGlass
                              ? AppTheme.glassBackground2
                              : (isDark ? AppTheme.darkBackground : AppTheme.lightSurface),
                          child: SafeArea(
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.local_shipping_rounded,
                                        color: AppTheme.primaryIndigo,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          context.org.companyName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  leading: Icon(
                                    Icons.search_rounded,
                                    color: isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo,
                                  ),
                                  title: const Text('Global Database Search'),
                                  onTap: () {
                                    Navigator.pop(context); // close the drawer
                                    _showGlobalSearchSheet(context, isDark);
                                  },
                                ),
                                ListTile(
                                  leading: Icon(themeIcon, color: themeColor),
                                  title: Text(themeTooltip),
                                  onTap: () => context.read<ThemeCubit>().toggleTheme(),
                                ),
                                const MockLiveSwitchTile(),
                              ],
                            ),
                          ),
                        ),
                  appBar: AppBar(
                    title: isWideScreen
                        ? Text(
                            switch (currentIndex) {
                              0 => 'Customers & Routes',
                              1 => 'Analytics & Dashboard',
                              2 => 'Operations Panel',
                              3 => 'Reports & Statements',
                              _ => 'Dashboard',
                            },
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : Row(
                            children: [
                              const Icon(
                                Icons.local_shipping_rounded,
                                color: AppTheme.primaryIndigo,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.org.companyName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                    actions: [
                      BlocBuilder<SyncBloc, SyncState>(
                        builder: (context, syncState) {
                          final isSyncing = syncState.isSyncing;
                          final hasPending = syncState.pendingCount > 0;
                          final syncColor = isSyncing
                              ? AppTheme.primaryIndigo
                              : (hasPending
                                    ? AppTheme.warningAmber
                                    : AppTheme.successEmerald);

                          return Tooltip(
                            message: isSyncing
                                ? 'Syncing… · Tap to open Sync Masters'
                                : (hasPending
                                      ? '${syncState.pendingCount} items pending · Tap to open Sync Masters'
                                      : 'All synced · Tap to open Sync Masters'),
                            child: InkWell(
                              onTap: () => _showMastersSyncPage(context),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: syncColor,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 72),
                                      child: Text(
                                        isSyncing
                                            ? 'Syncing'
                                            : (hasPending
                                                  ? '${syncState.pendingCount} Pending'
                                                  : 'Synced'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: syncColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      isSyncing
                                          ? Icons.sync_outlined
                                          : Icons.cloud_done_outlined,
                                      size: 15,
                                      color: syncColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  body: isWideScreen
                      ? Row(
                          children: [
                            _buildSidebar(
                              context,
                              currentIndex,
                              isDark,
                              isGlass,
                              themeIcon,
                              themeColor,
                              themeTooltip,
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
                            // Customers tab (index 0) is hidden from the bottom
                            // bar for now. Bar slots map to tab indices 1–3.
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
                                  icon: Icon(Icons.settings_suggest_outlined),
                                  activeIcon: Icon(Icons.settings_suggest),
                                  label: 'Operations',
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

  Widget _buildSidebar(
    BuildContext context,
    int currentIndex,
    bool isDark,
    bool isGlass,
    IconData themeIcon,
    Color themeColor,
    String themeTooltip,
  ) {
    final companyName = context.org.companyName;

    return Container(
      width: 260,
      color: isGlass
          ? AppTheme.glassBackground2.withValues(alpha: 0.8)
          : (isDark ? AppTheme.darkSurface : AppTheme.lightSurface),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping_rounded,
                    color: AppTheme.primaryIndigo,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          companyName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Van Sales System',
                          style: TextStyle(
                            fontSize: 11,
                            color: isGlass
                                ? AppTheme.glassTextSecondary
                                : (isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 0,
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Customers',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 1,
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 2,
                    icon: Icons.settings_suggest_outlined,
                    activeIcon: Icons.settings_suggest,
                    label: 'Operations',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 3,
                    icon: Icons.assessment_outlined,
                    activeIcon: Icons.assessment,
                    label: 'Reports',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.search_rounded,
                      color: isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo,
                    ),
                    title: const Text('Global Search', style: TextStyle(fontSize: 13)),
                    onTap: () => _showGlobalSearchSheet(context, isDark),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(themeIcon, color: themeColor),
                    title: Text(themeTooltip, style: const TextStyle(fontSize: 13)),
                    onTap: () => context.read<ThemeCubit>().toggleTheme(),
                  ),
                  const SizedBox(height: 8),
                  const MockLiveSwitchTile(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required BuildContext context,
    required int currentIndex,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isGlass,
    required bool isDark,
  }) {
    final isSelected = currentIndex == index;
    final activeColor = isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo;
    final inactiveColor = isGlass
        ? AppTheme.glassTextSecondary
        : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary);

    return InkWell(
      onTap: () => context.read<DashboardNavCubit>().setTab(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? (isGlass ? Colors.cyanAccent : (isDark ? AppTheme.darkText : AppTheme.lightText))
                      : inactiveColor,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
