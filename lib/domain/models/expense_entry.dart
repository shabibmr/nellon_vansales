import 'package:equatable/equatable.dart';

class ExpenseLineItem extends Equatable {
  final String category; // Fuel, Tolls, Meals, Maintenance, Miscellaneous
  final double amount;
  final String description;

  const ExpenseLineItem({
    required this.category,
    required this.amount,
    required this.description,
  });

  @override
  List<Object?> get props => [category, amount, description];
}

class ExpenseEntry extends Equatable {
  final String id;
  final DateTime date;
  final List<ExpenseLineItem> lines; // Multi-line expense claiming
  final String? receiptImagePath; // Path to locally stored receipt image
  final bool isPendingSync;

  const ExpenseEntry({
    required this.id,
    required this.date,
    required this.lines,
    this.receiptImagePath,
    this.isPendingSync = false,
  });

  // Calculate sum of lines
  double get amount => lines.fold(0.0, (sum, item) => sum + item.amount);

  ExpenseEntry copyWith({
    String? id,
    DateTime? date,
    List<ExpenseLineItem>? lines,
    String? receiptImagePath,
    bool? isPendingSync,
  }) {
    return ExpenseEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      lines: lines ?? this.lines,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => [
        id,
        date,
        lines,
        receiptImagePath,
        isPendingSync,
      ];
}
