import 'package:equatable/equatable.dart';

/// A single day's sales total, used to plot the 7-day trend chart.
class DailySalesPoint extends Equatable {
  final DateTime date;
  final double total;

  const DailySalesPoint({required this.date, required this.total});

  @override
  List<Object?> get props => [date, total];
}

class DailyStatsState extends Equatable {
  final double todaySales;
  final double todayPayments;
  final double todayExpenses;
  final double todayReturns;
  final double todayOrdersTotal;
  final int completedDeliveries;
  final List<DailySalesPoint> last7DaysSales;

  const DailyStatsState({
    this.todaySales = 0.0,
    this.todayPayments = 0.0,
    this.todayExpenses = 0.0,
    this.todayReturns = 0.0,
    this.todayOrdersTotal = 0.0,
    this.completedDeliveries = 0,
    this.last7DaysSales = const [],
  });

  @override
  List<Object?> get props => [
        todaySales,
        todayPayments,
        todayExpenses,
        todayReturns,
        todayOrdersTotal,
        completedDeliveries,
        last7DaysSales,
      ];
}
