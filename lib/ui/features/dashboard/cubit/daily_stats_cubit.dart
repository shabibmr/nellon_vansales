import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/repositories/sales_repository.dart';
import 'daily_stats_state.dart';

class DailyStatsCubit extends Cubit<DailyStatsState> {
  final SalesRepository salesRepository;

  DailyStatsCubit({required this.salesRepository})
      : super(const DailyStatsState()) {
    refresh();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final locA = a.toLocal();
    final locB = b.toLocal();
    return locA.year == locB.year &&
        locA.month == locB.month &&
        locA.day == locB.day;
  }

  void refresh() {
    try {
      final now = DateTime.now();

      final allInvoices = salesRepository.getLocalInvoices();
      final allReceipts = salesRepository.getLocalReceipts();
      final allExpenses = salesRepository.getLocalExpenses();
      final allReturns = salesRepository.getLocalReturns();
      final allOrders = salesRepository.getLocalOrders();

      final todaysInvoices =
          allInvoices.where((inv) => _isSameDay(inv.date, now)).toList();
      final todaysReceipts =
          allReceipts.where((rec) => _isSameDay(rec.date, now)).toList();
      final todaysExpenses =
          allExpenses.where((exp) => _isSameDay(exp.date, now)).toList();
      final todaysReturns =
          allReturns.where((ret) => _isSameDay(ret.date, now)).toList();
      final todaysOrders =
          allOrders.where((ord) => _isSameDay(ord.date, now)).toList();

      final todaySales =
          todaysInvoices.fold(0.0, (sum, item) => sum + item.total);
      final todayPayments =
          todaysReceipts.fold(0.0, (sum, item) => sum + item.amount);
      final todayExpenses =
          todaysExpenses.fold(0.0, (sum, item) => sum + item.amount);
      final todayReturns =
          todaysReturns.fold(0.0, (sum, item) => sum + item.total);
      final todayOrdersTotal =
          todaysOrders.fold(0.0, (sum, item) => sum + item.total);
      final completedDeliveries =
          todaysInvoices.map((inv) => inv.customerId).toSet().length;

      final today = DateTime(now.year, now.month, now.day);
      final last7DaysSales = List.generate(7, (i) {
        final day = today.subtract(Duration(days: 6 - i));
        final total = allInvoices
            .where((inv) => _isSameDay(inv.date, day))
            .fold(0.0, (sum, inv) => sum + inv.total);
        return DailySalesPoint(date: day, total: total);
      });

      emit(
        DailyStatsState(
          todaySales: todaySales,
          todayPayments: todayPayments,
          todayExpenses: todayExpenses,
          todayReturns: todayReturns,
          todayOrdersTotal: todayOrdersTotal,
          completedDeliveries: completedDeliveries,
          last7DaysSales: last7DaysSales,
        ),
      );
    } catch (_) {
      // Don't crash dashboard; keep last stats or zeros
    }
  }
}
