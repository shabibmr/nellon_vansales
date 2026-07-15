import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/hive_database_service.dart';
import 'daily_stats_state.dart';

class DailyStatsCubit extends Cubit<DailyStatsState> {
  final HiveDatabaseService dbService;

  DailyStatsCubit({required this.dbService}) : super(const DailyStatsState()) {
    refresh();
  }

  void refresh() {
    try {
      final invoices = dbService.getLocalInvoices();
      final receipts = dbService.getLocalReceipts();
      final expenses = dbService.getLocalExpenses();
      final returns = dbService.getLocalReturns();

      final todaySales = invoices.fold(0.0, (sum, item) => sum + item.total);
      final todayPayments = receipts.fold(0.0, (sum, item) => sum + item.amount);
      final todayExpenses = expenses.fold(0.0, (sum, item) => sum + item.amount);
      final todayReturns = returns.fold(0.0, (sum, item) => sum + item.total);
      final completedDeliveries = invoices
          .map((inv) => inv.customerId)
          .toSet()
          .length;

      emit(DailyStatsState(
        todaySales: todaySales,
        todayPayments: todayPayments,
        todayExpenses: todayExpenses,
        todayReturns: todayReturns,
        completedDeliveries: completedDeliveries,
      ));
    } catch (_) {
      // Don't crash dashboard; keep last stats or zeros
    }
  }
}
