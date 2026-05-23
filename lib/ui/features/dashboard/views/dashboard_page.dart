import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/theme/theme_cubit.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/injection.dart';
import '../../route/bloc/route_bloc.dart';
import '../../sync/bloc/sync_bloc.dart';
import '../widgets/route_sequence_tab.dart';
import '../widgets/analytics_reports_tab.dart';
import '../widgets/operations_tab.dart';
import '../widgets/global_search_sheet.dart';
import '../widgets/item_details_dialog.dart';
import '../widgets/client_operations_sheet.dart';
import '../widgets/invoice_flow_sheet.dart';
import '../widgets/receipt_payment_dialog.dart';
import '../widgets/sales_return_dialog.dart';
import '../widgets/create_customer_dialog.dart';
import '../widgets/expense_log_dialog.dart';
import '../widgets/cash_closing_dialog.dart';

class DashboardPage extends StatefulWidget {
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
  int _completedDeliveries = 0;

  @override
  void initState() {
    super.initState();
    _loadDailyStats();
  }

  void _loadDailyStats() {
    final invoices = _db.getLocalInvoices();
    final receipts = _db.getLocalReceipts();
    final expenses = _db.getLocalExpenses();

    setState(() {
      _todaySales = invoices.fold(0.0, (sum, item) => sum + item.total);
      _todayPayments = receipts.fold(0.0, (sum, item) => sum + item.amount);
      _todayExpenses = expenses.fold(0.0, (sum, item) => sum + item.amount);
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

  void _showCreateCustomerForm(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => CreateCustomerDialog(
        onCustomerCreated: () {
          _loadDailyStats();
        },
      ),
    );
  }

  void _showExpenseLogForm(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => ExpenseLogDialog(
        isDark: isDark,
        onExpenseLogged: () {
          _loadDailyStats();
        },
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabs = [
      RouteSequenceTab(
        isDark: isDark,
        onCustomerTap: (customer) => _showClientOperationsSheet(customer, isDark),
      ),
      AnalyticsReportsTab(
        isDark: isDark,
        todaySales: _todaySales,
        todayPayments: _todayPayments,
        todayExpenses: _todayExpenses,
        completedDeliveries: _completedDeliveries,
      ),
      OperationsTab(
        isDark: isDark,
        onCreateCustomer: () => _showCreateCustomerForm(isDark),
        onLogExpense: () => _showExpenseLogForm(isDark),
        onCashClosing: () => _showCashClosingForm(isDark),
        onSwitchRoute: () => context.read<RouteBloc>().add(const SelectActiveRoute(null)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_shipping_rounded, color: AppTheme.primaryIndigo),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Van Sales Pro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  _db.activeRouteId == 'route_north'
                      ? 'North Downtown Sequence'
                      : (_db.activeRouteId == 'route_south' ? 'South Retail Hub' : 'Custom Route Sequence'),
                  style: const TextStyle(fontSize: 11, color: AppTheme.primaryIndigo, fontWeight: FontWeight.normal),
                )
              ],
            )
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Global Database Search',
            icon: const Icon(Icons.search_rounded, color: AppTheme.primaryIndigo),
            onPressed: () => _showGlobalSearchSheet(isDark),
          ),
          BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, themeMode) {
              final isDark = themeMode == ThemeMode.dark;
              return IconButton(
                tooltip: 'Toggle Theme',
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: isDark ? Colors.amber : AppTheme.primaryIndigo,
                ),
                onPressed: () {
                  context.read<ThemeCubit>().toggleTheme();
                },
              );
            },
          ),
          BlocBuilder<SyncBloc, SyncState>(
            builder: (context, syncState) {
              final isSyncing = syncState.isSyncing;
              final hasPending = syncState.pendingCount > 0;

              return InkWell(
                onTap: () {
                  context.read<SyncBloc>().add(TriggerSync());
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSyncing
                              ? AppTheme.primaryIndigo
                              : (hasPending ? AppTheme.warningAmber : AppTheme.successEmerald),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSyncing
                            ? 'Syncing...'
                            : (hasPending ? '${syncState.pendingCount} Pending' : 'Synced'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: hasPending ? AppTheme.warningAmber : AppTheme.successEmerald,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isSyncing ? Icons.sync_outlined : Icons.cloud_done_outlined,
                        size: 16,
                        color: hasPending ? AppTheme.warningAmber : AppTheme.successEmerald,
                      )
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8)
        ],
      ),
      body: tabs[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
          selectedItemColor: AppTheme.primaryIndigo,
          unselectedItemColor: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          elevation: 0,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.route_outlined),
              activeIcon: Icon(Icons.route),
              label: 'Route Clients',
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
    );
  }
}
