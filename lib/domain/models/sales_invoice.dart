import 'package:equatable/equatable.dart';
import 'item.dart';

class InvoiceLineItem extends Equatable {
  final Item item;
  final int quantity;
  final double rate;
  final double taxPercentage;

  const InvoiceLineItem({
    required this.item,
    required this.quantity,
    required this.rate,
    required this.taxPercentage,
  });

  double get subTotal => rate * quantity;
  double get taxAmount => subTotal * (taxPercentage / 100);
  final double discount = 0.0;
  double get total => subTotal + taxAmount - discount;

  InvoiceLineItem copyWith({
    Item? item,
    int? quantity,
    double? rate,
    double? taxPercentage,
  }) {
    return InvoiceLineItem(
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
      rate: rate ?? this.rate,
      taxPercentage: taxPercentage ?? this.taxPercentage,
    );
  }

  @override
  List<Object?> get props => [item, quantity, rate, taxPercentage];
}

class SalesInvoice extends Equatable {
  final String id;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final DateTime date;
  final DateTime dueDate;
  final List<InvoiceLineItem> items;
  final String notes;
  final bool isPendingSync;

  const SalesInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.dueDate,
    required this.items,
    required this.notes,
    this.isPendingSync = false,
  });

  double get subTotal => items.fold(0.0, (sum, item) => sum + item.subTotal);
  double get taxTotal => items.fold(0.0, (sum, item) => sum + item.taxAmount);
  double get total => items.fold(0.0, (sum, item) => sum + item.total);

  SalesInvoice copyWith({
    String? id,
    String? invoiceNumber,
    String? customerId,
    String? customerName,
    DateTime? date,
    DateTime? dueDate,
    List<InvoiceLineItem>? items,
    String? notes,
    bool? isPendingSync,
  }) {
    return SalesInvoice(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      items: items ?? this.items,
      notes: notes ?? this.notes,
      isPendingSync: isPendingSync ?? this.isPendingSync,
    );
  }

  @override
  List<Object?> get props => [
        id,
        invoiceNumber,
        customerId,
        customerName,
        date,
        dueDate,
        items,
        notes,
        isPendingSync,
      ];
}
