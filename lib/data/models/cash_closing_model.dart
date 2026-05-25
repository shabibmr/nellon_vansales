import '../../domain/models/cash_closing.dart';

/// Data transfer object representing the daily [CashClosing] reconciliation.
///
/// Handles saving daily balance parameters, calculated expected balances, and notes to local JSON/Hive storage.
class CashClosingModel extends CashClosing {
  /// Creates a new [CashClosingModel] instance.
  const CashClosingModel({
    required super.id,
    required super.date,
    required super.openingBalance,
    required super.totalSalesInvoices,
    required super.totalReceiptsCollected,
    required super.totalExpenses,
    required super.closingBalance,
    required super.notes,
    super.isPendingSync,
  });

  /// Factory constructor to parse local database JSON maps into a [CashClosingModel].
  factory CashClosingModel.fromJson(Map<String, dynamic> json) {
    return CashClosingModel(
      id: json['id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      openingBalance: (json['openingBalance'] ?? 0.0).toDouble(),
      totalSalesInvoices: (json['totalSalesInvoices'] ?? 0.0).toDouble(),
      totalReceiptsCollected: (json['totalReceiptsCollected'] ?? 0.0).toDouble(),
      totalExpenses: (json['totalExpenses'] ?? 0.0).toDouble(),
      closingBalance: (json['closingBalance'] ?? 0.0).toDouble(),
      notes: json['notes'] ?? '',
      isPendingSync: json['isPendingSync'] ?? false,
    );
  }

  /// Converts this [CashClosingModel] instance into a serializable JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'openingBalance': openingBalance,
      'totalSalesInvoices': totalSalesInvoices,
      'totalReceiptsCollected': totalReceiptsCollected,
      'totalExpenses': totalExpenses,
      'closingBalance': closingBalance,
      'expectedClosingBalance': expectedClosingBalance,
      'reportedDifference': reportedDifference,
      'notes': notes,
      'isPendingSync': isPendingSync,
    };
  }

  /// Translates a base domain [CashClosing] entity into its [CashClosingModel] representation.
  factory CashClosingModel.fromDomain(CashClosing closing) {
    return CashClosingModel(
      id: closing.id,
      date: closing.date,
      openingBalance: closing.openingBalance,
      totalSalesInvoices: closing.totalSalesInvoices,
      totalReceiptsCollected: closing.totalReceiptsCollected,
      totalExpenses: closing.totalExpenses,
      closingBalance: closing.closingBalance,
      notes: closing.notes,
      isPendingSync: closing.isPendingSync,
    );
  }
}

