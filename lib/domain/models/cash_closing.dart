import 'package:equatable/equatable.dart';

class CashClosing extends Equatable {
  final String id;
  final DateTime date;
  final double openingBalance;
  final double totalSalesInvoices;
  final double totalReceiptsCollected;
  final double totalExpenses;
  final double closingBalance; // Physical cash counted in hand
  final String notes;
  final bool isPendingSync;

  const CashClosing({
    required this.id,
    required this.date,
    required this.openingBalance,
    required this.totalSalesInvoices,
    required this.totalReceiptsCollected,
    required this.totalExpenses,
    required this.closingBalance,
    required this.notes,
    this.isPendingSync = false,
  });

  double get expectedClosingBalance =>
      openingBalance + totalReceiptsCollected - totalExpenses;

  double get reportedDifference => closingBalance - expectedClosingBalance;

  CashClosing copyWith({
    String? id,
    DateTime? date,
    double? openingBalance,
    double? totalSalesInvoices,
    double? totalReceiptsCollected,
    double? totalExpenses,
    double? closingBalance,
    String? notes,
    bool? isPendingSync,
  }) {
    return CashClosing(
      id: id ?? this.id,
      date: date ?? this.date,
      openingBalance: openingBalance ?? this.openingBalance,
      totalSalesInvoices: totalSalesInvoices ?? this.totalSalesInvoices,
      totalReceiptsCollected: totalReceiptsCollected ?? this.totalReceiptsCollected,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      closingBalance: closingBalance ?? this.closingBalance,
      notes: notes ?? this.notes,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => [
        id,
        date,
        openingBalance,
        totalSalesInvoices,
        totalReceiptsCollected,
        totalExpenses,
        closingBalance,
        notes,
        isPendingSync,
      ];
}
