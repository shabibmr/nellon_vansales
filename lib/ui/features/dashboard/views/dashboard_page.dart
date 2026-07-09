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

/// The central workspace of the Van Sales application.
///
/// Features a multi-tab view (route sequence, dashboard, operations, and reports)
/// displaying real-time daily sales, collections, route stats, and triggers to create new entities.
class DashboardPage extends StatefulWidget {
  /// Creates a new [DashboardPage].
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentIndex = 0;
  final HiveDatabaseService _db = sl<HiveDatabaseService>();

  // Daily Statistics
  double _todaySales = 0.0;
  double _todayPayments = 0.0;
  double _todayExpenses = 0.0;
  double _todayReturns = 0.0;
  int _completedDeliveries = 0;

  @override
  void initState() {
    super.initState();
    _loadDailyStats();
  }

  /// Queries the local Hive database for daily records and accumulates totals to display stats.
  void _loadDailyStats() {
    final invoices = _db.getLocalInvoices();
    final receipts = _db.getLocalReceipts();
    final expenses = _db.getLocalExpenses();
    final returns = _db.getLocalReturns();

    setState(() {
      _todaySales = invoices.fold(0.0, (sum, item) => sum + item.total);
      _todayPayments = receipts.fold(0.0, (sum, item) => sum + item.amount);
      _todayExpenses = expenses.fold(0.0, (sum, item) => sum + item.amount);
      _todayReturns = returns.fold(0.0, (sum, item) => sum + item.total);
      _completedDeliveries = invoices
          .map((inv) => inv.customerId)
          .toSet()
          .length;
    });
  }

  void _showGlobalSearchSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return GlobalSearchSheet(
          isDark: isDark,
          onCustomerSelected: (customer) {
            Navigator.pop(context); // Close search
            _showClientOperationsSheet(
              customer,
              isDark,
            ); // Open customer actions sheet!
          },
          onItemSelected: (item) {
            Navigator.pop(context); // Close search
            _showItemDetailsDialog(item, isDark); // Open quick details dialog
          },
        );
      },
    );
  }

  void _showItemDetailsDialog(Item item, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => ItemDetailsDialog(item: item),
    );
  }

  void _showClientOperationsSheet(Customer customer, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return ClientOperationsSheet(
          customer: customer,
          isDark: isDark,
          onNewInvoiceTap: () {
            Navigator.pop(context);
            _launchInvoiceFlow(customer, isDark);
          },
          onNewOrderTap: () {
            Navigator.pop(context);
            _launchSalesOrderFlow(customer);
          },
          onReceiptPaymentTap: () {
            Navigator.pop(context);
            _launchPaymentFlow(customer, isDark);
          },
          onSalesReturnTap: () {
            Navigator.pop(context);
            _launchSalesReturnFlow(customer, isDark);
          },
        );
      },
    );
  }

  void _launchSalesOrderFlow(Customer customer) {
    final bloc = context.read<SalesOrderBloc>();
    bloc.add(StartNewOrder());
    bloc.add(UpdateOrderCustomer(customer));

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SalesOrderEditorPage()),
    ).then((_) {
      _loadDailyStats();
    });
  }

  void _launchInvoiceFlow(Customer customer, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return InvoiceFlowSheet(
          customer: customer,
          isDark: isDark,
          onInvoiceSubmitted: () {
            _loadDailyStats();
          },
        );
      },
    );
  }

  void _launchPaymentFlow(Customer customer, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => ReceiptPaymentDialog(
        customer: customer,
        onPaymentLogged: () {
          _loadDailyStats();
        },
      ),
    );
  }

  void _launchSalesReturnFlow(Customer customer, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => SalesReturnDialog(
        customer: customer,
        onReturnConfirmed: () {
          _loadDailyStats();
        },
      ),
    );
  }

  void _showItemSalesReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ItemSalesReportPage()),
    );
  }

  void _showAgingReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgingReceivablesReportPage()),
    );
  }

  void _showStockReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockReportPage()),
    );
  }

  void _showTransactionsSummaryReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionsSummaryReportPage()),
    );
  }

  void _showExpenseSummaryReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseSummaryReportPage()),
    );
  }

  void _showInvoiceReceiptsSummaryReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InvoiceReceiptsSummaryReportPage(),
      ),
    );
  }

  void _showSalesSummaryByCustomerValueReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SalesSummaryByCustomerValueReportPage(),
      ),
    );
  }

  void _showSalesSummaryByCustomerItemReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SalesSummaryByCustomerItemReportPage(),
      ),
    );
  }

  void _showItemwiseOrdersSummaryReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemwiseOrdersSummaryReportPage(),
      ),
    );
  }

  void _showOrdersSummaryByCustomerReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrdersSummaryByCustomerReportPage(),
      ),
    );
  }

  void _showOrdersReadyReport() {
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

  void _showPendingOrdersReport() {
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

  void _showOrdersInvoicedReport() {
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

  void _showOrdersDelayedReport() {
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

  void _showItemwiseReturnsSummaryReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemwiseReturnsSummaryReportPage(),
      ),
    );
  }

  void _showCustomerwiseReturnsSummaryReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerwiseReturnsSummaryReportPage(),
      ),
    );
  }

  void _showSalesReturnListPage() {
    context.read<SalesReturnBloc>().add(LoadReturns());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SalesReturnListPage()),
    ).then((_) => _loadDailyStats());
  }

  void _showExpenseListPage() {
    context.read<ExpenseBloc>().add(LoadExpenses());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseListPage()),
    ).then((_) => _loadDailyStats());
  }

  void _showReceiptListPage() {
    context.read<ReceiptBloc>().add(LoadReceipts());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReceiptListPage()),
    ).then((_) => _loadDailyStats());
  }

  void _showCustomerLedgerPage() {
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

  void _showMastersSyncPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MastersSyncPage()),
    );
  }

  void _showIssueToVanPage() {
    context.read<StockTransferBloc>().add(LoadIssueGrid());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IssueToVanPage()),
    ).then((_) => _loadDailyStats());
  }

  void _showStockUnloadingPage() {
    context.read<StockTransferBloc>().add(LoadUnloadGrid());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockUnloadingPage()),
    ).then((_) => _loadDailyStats());
  }

  void _showCashClosingForm(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => CashClosingDialog(
        todaySales: _todaySales,
        todayPayments: _todayPayments,
        todayExpenses: _todayExpenses,
        onSessionReconciled: () {
          _loadDailyStats();
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

    final tabs = [
      RouteSequenceTab(
        isDark: isDark || isGlass,
        onCustomerTap: (customer) =>
            _showClientOperationsSheet(customer, isDark),
      ),
      AnalyticsReportsTab(
        isDark: isDark,
        isGlass: isGlass,
        todaySales: _todaySales,
        todayPayments: _todayPayments,
        todayExpenses: _todayExpenses,
        todayReturns: _todayReturns,
        completedDeliveries: _completedDeliveries,
      ),
      OperationsTab(
        isDark: isDark || isGlass,
        onCashClosing: () => _showCashClosingForm(isDark),
        onManageExpenses: _showExpenseListPage,
        onManageReceipts: _showReceiptListPage,
        onManageReturns: _showSalesReturnListPage,
        onManageInvoices: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SalesInvoiceListPage(),
            ),
          ).then((_) {
            _loadDailyStats();
          });
        },
        onManageOrders: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SalesOrderListPage()),
          ).then((_) {
            _loadDailyStats();
          });
        },
        onIssueToVan: _showIssueToVanPage,
        onStockUnloading: _showStockUnloadingPage,
      ),
      ReportsTab(
        isDark: isDark,
        onItemSalesReport: _showItemSalesReport,
        onCustomerLedger: _showCustomerLedgerPage,
        onAgingReport: _showAgingReport,
        onStockReport: _showStockReport,
        onTransactionsSummaryReport: _showTransactionsSummaryReport,
        onExpenseSummaryReport: _showExpenseSummaryReport,
        onInvoiceReceiptsSummaryReport: _showInvoiceReceiptsSummaryReport,
        onSalesSummaryByCustomerValueReport:
            _showSalesSummaryByCustomerValueReport,
        onSalesSummaryByCustomerItemReport:
            _showSalesSummaryByCustomerItemReport,
        onItemwiseOrdersSummaryReport: _showItemwiseOrdersSummaryReport,
        onOrdersSummaryByCustomerReport: _showOrdersSummaryByCustomerReport,
        onOrdersReadyReport: _showOrdersReadyReport,
        onPendingOrdersReport: _showPendingOrdersReport,
        onOrdersInvoicedReport: _showOrdersInvoicedReport,
        onOrdersDelayedReport: _showOrdersDelayedReport,
        onItemwiseReturnsSummaryReport: _showItemwiseReturnsSummaryReport,
        onCustomerwiseReturnsSummaryReport:
            _showCustomerwiseReturnsSummaryReport,
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
                            _showGlobalSearchSheet(isDark);
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
                    switch (_currentIndex) {
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
                      onTap: _showMastersSyncPage,
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
                      isDark,
                      isGlass,
                      themeIcon,
                      themeColor,
                      themeTooltip,
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: tabs[_currentIndex],
                    ),
                  ],
                )
              : tabs[_currentIndex],
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
                      currentIndex: _currentIndex,
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
                      onTap: (index) {
                        setState(() {
                          _currentIndex = index;
                        });
                      },
                      type: BottomNavigationBarType.fixed,
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.people_outline),
                          activeIcon: Icon(Icons.people),
                          label: 'Customers',
                        ),
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
  }

  Widget _buildSidebar(
    BuildContext context,
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
                    index: 0,
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Customers',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    index: 1,
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    index: 2,
                    icon: Icons.settings_suggest_outlined,
                    activeIcon: Icons.settings_suggest,
                    label: 'Operations',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
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
                    onTap: () => _showGlobalSearchSheet(isDark),
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
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isGlass,
    required bool isDark,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo;
    final inactiveColor = isGlass
        ? AppTheme.glassTextSecondary
        : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary);

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.1)
              : Colors.transparent,
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
