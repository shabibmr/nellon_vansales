import 'package:equatable/equatable.dart';

/// Represents a single categorical expense charge inside an overall expense entry ledger.
class ExpenseLineItem extends Equatable {
  /// The user-facing classification category (e.g., Fuel, Tolls, Meals, Maintenance, Miscellaneous).
  final String category;

  /// The cost of this specific item line.
  final double amount;

  /// Brief description detailing why this expense line was incurred.
  final String description;

  /// Creates a new [ExpenseLineItem].
  const ExpenseLineItem({
    required this.category,
    required this.amount,
    required this.description,
  });

  @override
  List<Object?> get props => [category, amount, description];
}

/// Represents a multi-line expense log voucher created during a route delivery.
///
/// Bundles multiple line item expenditures, supports attachment of receipt images, and tracks sync status.
class ExpenseEntry extends Equatable {
  /// Unique expense record identifier.
  final String id;

  /// The date when the expense log was created.
  final DateTime date;

  /// The collection of line item expenses detailed inside this voucher.
  final List<ExpenseLineItem> lines;

  /// Local filesystem path where the camera receipt screenshot or file is cached.
  final String? receiptImagePath;

  /// Flag indicating if the expense voucher has been uploaded/synchronized with the server.
  final bool isPendingSync;

  /// The Zoho Location ID of the salesperson/van that logged this expense.
  final String? locationId;

  /// Creates a new [ExpenseEntry] voucher.
  const ExpenseEntry({
    required this.id,
    required this.date,
    required this.lines,
    this.receiptImagePath,
    this.isPendingSync = false,
    this.locationId,
  });

  /// Computes the total combined cost of all line items contained in this entry.
  double get amount => lines.fold(0.0, (sum, item) => sum + item.amount);

  /// Creates a copy of this [ExpenseEntry] with replaced values for specific fields.
  ExpenseEntry copyWith({
    String? id,
    DateTime? date,
    List<ExpenseLineItem>? lines,
    String? receiptImagePath,
    bool? isPendingSync,
    String? locationId,
  }) {
    return ExpenseEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      lines: lines ?? this.lines,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      locationId: locationId ?? this.locationId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    date,
    lines,
    receiptImagePath,
    isPendingSync,
    locationId,
  ];
}
