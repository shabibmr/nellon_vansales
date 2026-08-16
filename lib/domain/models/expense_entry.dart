import 'package:equatable/equatable.dart';
import '../utils/money_math.dart';

/// Represents a single categorical expense charge inside an overall expense entry ledger.
class ExpenseLineItem extends Equatable {
  /// The user-facing classification category (e.g., Fuel, Tolls, Maintenance, Parking fee).
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

  /// The permanent Zoho `expense_id`, populated once the expense syncs.
  final String? zohoExpenseId;

  /// The Zoho Location ID of the salesperson/van that logged this expense.
  final String? locationId;

  /// Grand total from Zoho list headers when [lines] are not loaded.
  final double? listedTotal;

  /// Category from Zoho list header (`account_name`) when [lines] are empty.
  final String listedCategory;

  /// Description from Zoho list header when [lines] are empty.
  final String listedDescription;

  /// Creates a new [ExpenseEntry] voucher.
  const ExpenseEntry({
    required this.id,
    required this.date,
    required this.lines,
    this.receiptImagePath,
    this.isPendingSync = false,
    this.zohoExpenseId,
    this.locationId,
    this.listedTotal,
    this.listedCategory = '',
    this.listedDescription = '',
  });

  /// Combined cost: line-derived when [lines] exist, else [listedTotal].
  double get amount {
    if (lines.isNotEmpty) {
      return roundMoney(lines.fold(0.0, (sum, item) => sum + item.amount));
    }
    if (listedTotal != null) return roundMoney(listedTotal!);
    return 0.0;
  }

  /// Category for list cards: first line, else header [listedCategory].
  String get displayCategory {
    if (lines.isNotEmpty) return lines.first.category;
    if (listedCategory.isNotEmpty) return listedCategory;
    return 'Expense';
  }

  /// Description for list cards: first line, else header [listedDescription].
  String get displayDescription {
    if (lines.isNotEmpty) return lines.first.description;
    return listedDescription;
  }

  /// Creates a copy of this [ExpenseEntry] with replaced values for specific fields.
  ExpenseEntry copyWith({
    String? id,
    DateTime? date,
    List<ExpenseLineItem>? lines,
    String? receiptImagePath,
    bool? isPendingSync,
    String? zohoExpenseId,
    String? locationId,
    double? listedTotal,
    bool clearListedTotal = false,
    String? listedCategory,
    String? listedDescription,
  }) {
    return ExpenseEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      lines: lines ?? this.lines,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      zohoExpenseId: zohoExpenseId ?? this.zohoExpenseId,
      locationId: locationId ?? this.locationId,
      listedTotal: clearListedTotal ? null : (listedTotal ?? this.listedTotal),
      listedCategory: listedCategory ?? this.listedCategory,
      listedDescription: listedDescription ?? this.listedDescription,
    );
  }

  @override
  List<Object?> get props => [
    id,
    date,
    lines,
    receiptImagePath,
    isPendingSync,
    zohoExpenseId,
    locationId,
    listedTotal,
    listedCategory,
    listedDescription,
  ];
}
