import 'package:equatable/equatable.dart';

class DailyStatsState extends Equatable {
  final double todaySales;
  final double todayPayments;
  final double todayExpenses;
  final double todayReturns;
  final int completedDeliveries;

  const DailyStatsState({
    this.todaySales = 0.0,
    this.todayPayments = 0.0,
    this.todayExpenses = 0.0,
    this.todayReturns = 0.0,
    this.completedDeliveries = 0,
  });

  @override
  List<Object?> get props => [
        todaySales,
        todayPayments,
        todayExpenses,
        todayReturns,
        completedDeliveries,
      ];
}
