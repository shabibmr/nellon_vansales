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
import '../../reports/views/item_sales_report_page.dart';
import '../../reports/views/aging_receivables_report_page.dart';
import '../../ledger/bloc/customer_ledger_bloc.dart';
import '../../ledger/views/customer_ledger_page.dart';
import '../../sync/views/masters_sync_page.dart';
import '../../../core/extensions/org_context_extension.dart';

/// The central workspace of the Van Sales application.
///
/// Features a multi-tab view (Route sequence, operations, and analytical reporting)
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
      _completedDeliveries = invoices.map((inv) => inv.customerId).toSet().length;
    });
  }

  void _showGlobalSearchSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return GlobalSearchSheet(
          isDark: isDark,
          onCustomerSelected: (customer) {
            Navigator.pop(context); // Close search
            _showClientOperationsSheet(customer, isDark); // Open customer actions sheet!
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
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
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
      MaterialPageRoute(
        builder: (context) => const SalesOrderEditorPage(),
      ),
    ).then((_) {
      _loadDailyStats();
    });
  }

  void _launchInvoiceFlow(Customer customer, bool isDark) {
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
      MaterialPageRoute(builder: (_) => BlocProvider.value(
        value: context.read<CustomerLedgerBloc>(),
        child: const CustomerLedgerPage(),
      )),
    );
  }

  void _showMastersSyncPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MastersSyncPage()),
    );
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
      AppThemeMode.light => (Icons.dark_mode_outlined, AppTheme.primaryIndigo, 'Switch to Dark'),
      AppThemeMode.dark => (Icons.blur_on_rounded, Colors.amber, 'Switch to Glass'),
      AppThemeMode.glass => (Icons.light_mode_outlined, Colors.cyanAccent, 'Switch to Light'),
    };

    final tabs = [
      RouteSequenceTab(
        isDark: isDark || isGlass,
        onCustomerTap: (customer) => _showClientOperationsSheet(customer, isDark),
      ),
      AnalyticsReportsTab(
        isDark: isDark,
        isGlass: isGlass,
        todaySales: _todaySales,
        todayPayments: _todayPayments,
        todayExpenses: _todayExpenses,
        todayReturns: _todayReturns,
        completedDeliveries: _completedDeliveries,
        onItemSalesReport: _showItemSalesReport,
        onCustomerLedger: _showCustomerLedgerPage,
        onAgingReport: _showAgingReport,
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
            MaterialPageRoute(
              builder: (context) => const SalesOrderListPage(),
            ),
          ).then((_) {
            _loadDailyStats();
          });
        },
      ),
    ];

    return Scaffold(
      drawer: Drawer(
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
                    const Icon(Icons.local_shipping_rounded, color: AppTheme.primaryIndigo, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.org.companyName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_shipping_rounded, color: AppTheme.primaryIndigo, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.org.companyName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                  : (hasPending ? AppTheme.warningAmber : AppTheme.successEmerald);

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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: syncColor),
                        ),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 72),
                          child: Text(
                            isSyncing
                                ? 'Syncing'
                                : (hasPending ? '${syncState.pendingCount} Pending' : 'Synced'),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: syncColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          isSyncing ? Icons.sync_outlined : Icons.cloud_done_outlined,
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
      // The app-wide AnimatedGlowBackground (mounted in MaterialApp.builder)
      // now provides the animated backdrop for every theme, including glass.
      body: tabs[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isGlass
              ? AppTheme.glassBackground2
              : (isDark ? AppTheme.darkBackground : AppTheme.lightSurface),
          border: Border(
            top: BorderSide(
              color: isGlass
                  ? AppTheme.glassBorder
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            backgroundColor: Colors.transparent,
            selectedItemColor: isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo,
            unselectedItemColor: isGlass
                ? AppTheme.glassTextSecondary
                : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            elevation: 0,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Customers',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.analytics_outlined),
                activeIcon: Icon(Icons.analytics),
                label: 'Daily Reports',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_suggest_outlined),
                activeIcon: Icon(Icons.settings_suggest),
                label: 'Operations',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
