import '../../domain/models/cash_closing.dart';

class CashClosingModel extends CashClosing {
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
