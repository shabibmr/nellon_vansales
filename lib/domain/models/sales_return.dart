import 'package:equatable/equatable.dart';
import 'sales_invoice.dart';

class SalesReturnLineItem extends Equatable {
  final InvoiceLineItem invoiceLineItem;
  final int returnedQuantity;

  const SalesReturnLineItem({
    required this.invoiceLineItem,
    required this.returnedQuantity,
  });

  double get total => invoiceLineItem.rate * returnedQuantity;

  SalesReturnLineItem copyWith({
    InvoiceLineItem? invoiceLineItem,
    int? returnedQuantity,
  }) {
    return SalesReturnLineItem(
      invoiceLineItem: invoiceLineItem ?? this.invoiceLineItem,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
    );
  }

  @override
  List<Object?> get props => [invoiceLineItem, returnedQuantity];
}

class SalesReturn extends Equatable {
  final String id;
  final String creditNoteNumber;
  final String customerId;
  final String customerName;
  final DateTime date;
  final List<SalesReturnLineItem> items;
  final String reason;
  final bool isPendingSync;

  const SalesReturn({
    required this.id,
    required this.creditNoteNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.items,
    required this.reason,
    this.isPendingSync = false,
  });

  double get total => items.fold(0.0, (sum, item) => sum + item.total);

  SalesReturn copyWith({
    String? id,
    String? creditNoteNumber,
    String? customerId,
    String? customerName,
    DateTime? date,
    List<SalesReturnLineItem>? items,
    String? reason,
    bool? isPendingSync,
  }) {
    return SalesReturn(
      id: id ?? this.id,
      creditNoteNumber: creditNoteNumber ?? this.creditNoteNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      items: items ?? this.items,
      reason: reason ?? this.reason,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => [
        id,
        creditNoteNumber,
        customerId,
        customerName,
        date,
        items,
        reason,
        isPendingSync,
      ];
}
