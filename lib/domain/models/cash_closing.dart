import 'package:equatable/equatable.dart';

/// Represents a daily cash reconciliation record at the end of a sales route trip.
///
/// Tracks opening cash, operations-derived figures (invoices, collections, expenses), and
/// compares them against physical cash-in-hand to compute any variance/difference.
class CashClosing extends Equatable {
  /// Unique identifier of the cash closing record.
  final String id;

  /// The date-time when the cash closing was recorded.
  final DateTime date;

  /// The starting cash amount in the van for the day.
  final double openingBalance;

  /// Total amount of sales invoices generated on this route.
  final double totalSalesInvoices;

  /// Total cash collected from customers during the day.
  final double totalReceiptsCollected;

  /// Total expenses incurred and paid during the day.
  final double totalExpenses;

  /// Physical cash counted and actually in hand.
  final double closingBalance;

  /// Optional remarks or notes regarding differences, delays, or issues.
  final String notes;

  /// Flag indicating if the record is pending synchronization with the backend server.
  final bool isPendingSync;

  /// Creates a new [CashClosing] daily reconciliation object.
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

  /// Computes the expected closing balance mathematically based on starting cash, collections, and expenses.
  ///
  /// Formula: `openingBalance + totalReceiptsCollected - totalExpenses`
  double get expectedClosingBalance =>
      openingBalance + totalReceiptsCollected - totalExpenses;

  /// Computes the difference (variance) between the physically counted cash and the expected cash.
  ///
  /// A positive value represents a cash surplus, while a negative value represents a deficit (shortage).
  double get reportedDifference => closingBalance - expectedClosingBalance;

  /// Creates a copy of this [CashClosing] with replaced values for specific fields.
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

