import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/repositories/expense_repository.dart';
import '../../../../domain/repositories/invoice_repository.dart';
import '../../../../domain/repositories/receipt_repository.dart';
import '../../../../domain/repositories/sales_order_repository.dart';
import '../../../../domain/repositories/sales_return_repository.dart';
import '../cubit/daily_stats_cubit.dart';
import '../cubit/dashboard_nav_cubit.dart';
import '../cubit/list_layout_cubit.dart';
import '../widgets/dashboard_scaffold.dart';

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
          create: (context) => DailyStatsCubit(
            invoiceRepository: context.read<InvoiceRepository>(),
            expenseRepository: context.read<ExpenseRepository>(),
            receiptRepository: context.read<ReceiptRepository>(),
            salesReturnRepository: context.read<SalesReturnRepository>(),
            salesOrderRepository: context.read<SalesOrderRepository>(),
          ),
        ),
        BlocProvider<ListLayoutCubit>(
          create: (_) => ListLayoutCubit(),
        ),
      ],
      child: const DashboardScaffold(),
    );
  }
}
