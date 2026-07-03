import 'package:equatable/equatable.dart';

/// A single debit/credit entry in a customer's ledger statement.
class LedgerTransaction extends Equatable {
  final String transactionId;
  final String transactionNumber;
  final DateTime date;
  final String
  type; // 'invoice', 'payment', 'credit_note', 'debit_note', 'opening_balance'
  final double debit;
  final double credit;
  final double balance;
  final String description;

  const LedgerTransaction({
    required this.transactionId,
    required this.transactionNumber,
    required this.date,
    required this.type,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.description,
  });

  factory LedgerTransaction.fromJson(Map<String, dynamic> json) {
    return LedgerTransaction(
      transactionId: json['transaction_id'] ?? json['id'] ?? '',
      transactionNumber:
          json['transaction_number'] ?? json['reference_number'] ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'])
          : DateTime.now(),
      type: json['transaction_type'] ?? json['type'] ?? 'unknown',
      debit: (json['debit'] ?? json['debit_amount'] ?? 0.0).toDouble(),
      credit: (json['credit'] ?? json['credit_amount'] ?? 0.0).toDouble(),
      balance: (json['balance'] ?? json['running_balance'] ?? 0.0).toDouble(),
      description: json['description'] ?? json['reference_number'] ?? '',
    );
  }

  @override
  List<Object?> get props => [
    transactionId,
    transactionNumber,
    date,
    type,
    debit,
    credit,
    balance,
    description,
  ];
}

/// Full ledger statement for a customer covering a date range.
class CustomerLedger extends Equatable {
  final String customerId;
  final String customerName;
  final double openingBalance;
  final double closingBalance;
  final List<LedgerTransaction> transactions;

  const CustomerLedger({
    required this.customerId,
    required this.customerName,
    required this.openingBalance,
    required this.closingBalance,
    required this.transactions,
  });

  double get totalDebits => transactions.fold(0.0, (sum, t) => sum + t.debit);

  double get totalCredits => transactions.fold(0.0, (sum, t) => sum + t.credit);

  factory CustomerLedger.fromJson(
    Map<String, dynamic> json,
    String customerId,
  ) {
    final txList = (json['transactions'] as List? ?? [])
        .map((t) => LedgerTransaction.fromJson(Map<String, dynamic>.from(t)))
        .toList();

    return CustomerLedger(
      customerId: json['contact_id'] ?? customerId,
      customerName: json['contact_name'] ?? '',
      openingBalance: (json['opening_balance'] ?? 0.0).toDouble(),
      closingBalance: (json['closing_balance'] ?? 0.0).toDouble(),
      transactions: txList,
    );
  }

  @override
  List<Object?> get props => [
    customerId,
    customerName,
    openingBalance,
    closingBalance,
    transactions,
  ];
}
