import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/repositories/salesperson_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../expenses/bloc/expense_list_bloc.dart';
import '../../expenses/bloc/expense_list_event.dart';
import '../../expenses/views/expense_editor_page.dart';
import '../../expenses/views/expense_list_page.dart';
import '../../ledger/bloc/customer_ledger_bloc.dart';
import '../../ledger/views/customer_ledger_page.dart';
import '../../receipts/bloc/receipt_list_bloc.dart';
import '../../receipts/bloc/receipt_list_event.dart';
import '../../receipts/views/receipt_editor_page.dart';
import '../../receipts/views/receipt_list_page.dart';
import '../../reports/views/aging_receivables_report_page.dart';
import '../../reports/views/expense_summary_report_page.dart';
import '../../reports/views/invoice_receipts_summary_report_page.dart';
import '../../reports/views/item_sales_report_page.dart';
import '../../reports/views/itemwise_orders_summary_report_page.dart';
import '../../reports/views/itemwise_returns_summary_report_page.dart';
import '../../reports/views/customerwise_returns_summary_report_page.dart';
import '../../reports/views/order_status_report_page.dart';
import '../../reports/views/orders_summary_by_customer_report_page.dart';
import '../../reports/views/sales_summary_by_customer_item_report_page.dart';
import '../../reports/views/sales_summary_by_customer_value_report_page.dart';
import '../../reports/views/shipment_orders_report_page.dart';
import '../../reports/views/stock_report_page.dart';
import '../../reports/views/stock_transfer_history_report_page.dart';
import '../../reports/views/transactions_summary_report_page.dart';
import '../../sales_invoice/views/sales_invoice_editor_page.dart';
import '../../sales_invoice/views/sales_invoice_list_page.dart';
import '../../sales_order/views/sales_order_editor_page.dart';
import '../../sales_order/views/sales_order_list_page.dart';
import '../../sales_return/bloc/sales_return_list_bloc.dart';
import '../../sales_return/bloc/sales_return_list_event.dart';
import '../../sales_return/views/sales_return_editor_page.dart';
import '../../sales_return/views/sales_return_list_page.dart';
import '../../stock_transfer/bloc/stock_transfer_bloc.dart';
import '../../stock_transfer/views/issue_to_van_page.dart';
import '../../stock_transfer/views/stock_unloading_page.dart';
import '../../sync/views/masters_sync_page.dart';
import '../cubit/daily_stats_cubit.dart';
import 'cash_closing_dialog.dart';
import 'client_operations_sheet.dart';
import 'global_search_sheet.dart';
import 'invoice_flow_sheet.dart';
import 'item_details_dialog.dart';
import 'receipt_payment_dialog.dart';
import 'sales_return_dialog.dart';

abstract class DashboardNavHelpers {
  static void showGlobalSearchSheet(BuildContext context, bool isDark) {
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
            Navigator.pop(sheetCtx);
            showClientOperationsSheet(context, customer, isDark);
          },
          onItemSelected: (item) {
            Navigator.pop(sheetCtx);
            showItemDetailsDialog(context, item, isDark);
          },
        );
      },
    );
  }

  static void showItemDetailsDialog(BuildContext context, Item item, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => ItemDetailsDialog(item: item),
    );
  }

  static void showClientOperationsSheet(BuildContext context, Customer customer, bool isDark) {
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
          ordersOnly: context.read<SalespersonRepository>().isOrdersOnlyMode,
          onBlocked: () => blockIfOrdersOnly(context),
          onNewInvoiceTap: () {
            Navigator.pop(sheetCtx);
            launchInvoiceFlow(context, dailyStatsCubit, customer, isDark);
          },
          onNewOrderTap: () {
            Navigator.pop(sheetCtx);
            launchSalesOrderFlow(context, dailyStatsCubit, customer);
          },
          onReceiptPaymentTap: () {
            Navigator.pop(sheetCtx);
            launchPaymentFlow(context, dailyStatsCubit, customer, isDark);
          },
          onSalesReturnTap: () {
            Navigator.pop(sheetCtx);
            launchSalesReturnFlow(context, dailyStatsCubit, customer, isDark);
          },
        );
      },
    );
  }

  static void launchSalesOrderFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer) {
    SalesOrderEditorPage.open(
      context,
      prefillCustomer: customer,
    ).then((_) {
      statsCubit.refresh();
    });
  }

  static void launchInvoiceFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer, bool isDark) {
    if (blockIfOrdersOnly(context)) return;
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

  static void launchPaymentFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer, bool isDark) {
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

  static void launchSalesReturnFlow(BuildContext context, DailyStatsCubit statsCubit, Customer customer, bool isDark) {
    if (blockIfOrdersOnly(context)) return;
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

  static void showItemSalesReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ItemSalesReportPage()),
    );
  }

  static void showAgingReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgingReceivablesReportPage()),
    );
  }

  static void showStockReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockReportPage()),
    );
  }

  static void showStockTransferHistoryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StockTransferHistoryReportPage(),
      ),
    );
  }

  static void showTransactionsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionsSummaryReportPage()),
    );
  }

  static void showExpenseSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseSummaryReportPage()),
    );
  }

  static void showInvoiceReceiptsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InvoiceReceiptsSummaryReportPage(),
      ),
    );
  }

  static void showSalesSummaryByCustomerValueReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SalesSummaryByCustomerValueReportPage(),
      ),
    );
  }

  static void showSalesSummaryByCustomerItemReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SalesSummaryByCustomerItemReportPage(),
      ),
    );
  }

  static void showItemwiseOrdersSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemwiseOrdersSummaryReportPage(),
      ),
    );
  }

  static void showOrdersSummaryByCustomerReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrdersSummaryByCustomerReportPage(),
      ),
    );
  }

  static void showOrdersByShipmentDateReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShipmentOrdersReportPage()),
    );
  }

  static void showOrdersReadyReport(BuildContext context) {
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

  static void showPendingOrdersReport(BuildContext context) {
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

  static void showOrdersInvoicedReport(BuildContext context) {
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

  static void showOrdersDelayedReport(BuildContext context) {
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

  static void showItemwiseReturnsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemwiseReturnsSummaryReportPage(),
      ),
    );
  }

  static void showCustomerwiseReturnsSummaryReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerwiseReturnsSummaryReportPage(),
      ),
    );
  }

  static void showSalesInvoiceListPage(BuildContext context, DailyStatsCubit statsCubit) {
    if (blockIfOrdersOnly(context)) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SalesInvoiceListPage()),
    ).then((_) {
      statsCubit.refresh();
    });
  }

  static void showSalesOrderListPage(BuildContext context, DailyStatsCubit statsCubit) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SalesOrderListPage()),
    ).then((_) {
      statsCubit.refresh();
    });
  }

  static void showSalesReturnListPage(BuildContext context, DailyStatsCubit statsCubit) {
    if (blockIfOrdersOnly(context)) return;
    context.read<SalesReturnListBloc>().add(const LoadReturns());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SalesReturnListPage()),
    ).then((_) => statsCubit.refresh());
  }

  static void showExpenseListPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<ExpenseListBloc>().add(const LoadExpenses());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpenseListPage()),
    ).then((_) => statsCubit.refresh());
  }

  static void showReceiptListPage(BuildContext context, DailyStatsCubit statsCubit) {
    context.read<ReceiptListBloc>().add(const LoadReceipts());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReceiptListPage()),
    ).then((_) => statsCubit.refresh());
  }

  static bool blockIfOrdersOnly(BuildContext context) {
    if (!context.read<SalespersonRepository>().isOrdersOnlyMode) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Van not assigned — invoices, returns, and stock moves are blocked. '
          'Sales Orders, Receipts, Expenses, and Cash Closing are available. '
          'Contact admin for a van.',
        ),
      ),
    );
    return true;
  }

  static void createNewInvoice(BuildContext context, DailyStatsCubit statsCubit) {
    if (blockIfOrdersOnly(context)) return;
    SalesInvoiceEditorPage.open(context).then((_) => statsCubit.refresh());
  }

  static void createNewOrder(BuildContext context, DailyStatsCubit statsCubit) {
    SalesOrderEditorPage.open(context).then((_) => statsCubit.refresh());
  }

  static void createNewExpense(BuildContext context, DailyStatsCubit statsCubit) {
    ExpenseEditorPage.open(context).then((_) => statsCubit.refresh());
  }

  static void createNewReceipt(BuildContext context, DailyStatsCubit statsCubit) {
    ReceiptEditorPage.open(context).then((_) => statsCubit.refresh());
  }

  static void createNewReturn(BuildContext context, DailyStatsCubit statsCubit) {
    if (blockIfOrdersOnly(context)) return;
    SalesReturnEditorPage.open(context).then((_) => statsCubit.refresh());
  }

  static void showCustomerLedgerPage(BuildContext context) {
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

  static void showMastersSyncPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MastersSyncPage()),
    );
  }

  static void showIssueToVanPage(BuildContext context, DailyStatsCubit statsCubit) {
    if (blockIfOrdersOnly(context)) return;
    context.read<StockTransferBloc>().add(LoadIssueGrid());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IssueToVanPage()),
    ).then((_) => statsCubit.refresh());
  }

  static void showStockUnloadingPage(BuildContext context, DailyStatsCubit statsCubit) {
    if (blockIfOrdersOnly(context)) return;
    context.read<StockTransferBloc>().add(LoadUnloadGrid());
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockUnloadingPage()),
    ).then((_) => statsCubit.refresh());
  }

  static void showCashClosingForm(BuildContext context, DailyStatsCubit statsCubit, double todaySales, double todayPayments, double todayExpenses) {
    CashClosingDialog.show(
      context,
      todaySales: todaySales,
      todayPayments: todayPayments,
      todayExpenses: todayExpenses,
      onSessionReconciled: () {
        statsCubit.refresh();
      },
    );
  }
}
