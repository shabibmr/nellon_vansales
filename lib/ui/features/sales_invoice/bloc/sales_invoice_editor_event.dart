import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_invoice.dart';
import '../../../../domain/models/sales_order.dart';

/// Base class for events handled by [SalesInvoiceEditorBloc].
abstract class SalesInvoiceEditorEvent extends Equatable {
  const SalesInvoiceEditorEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a blank form for a new sales invoice.
class StartNewInvoice extends SalesInvoiceEditorEvent {
  final Customer? customer;

  const StartNewInvoice({this.customer});

  @override
  List<Object?> get props => [customer];
}

/// Opens an existing invoice.
class OpenSalesInvoice extends SalesInvoiceEditorEvent {
  final SalesInvoice invoice;

  const OpenSalesInvoice(this.invoice);

  @override
  List<Object?> get props => [invoice];
}

/// Opens a new invoice pre-filled from a sales order being converted.
class StartInvoiceFromOrder extends SalesInvoiceEditorEvent {
  final SalesOrder order;

  const StartInvoiceFromOrder(this.order);

  @override
  List<Object?> get props => [order];
}

/// Re-attempts remote fetch for the invoice held in editor state.
class RetryLoadSalesInvoice extends SalesInvoiceEditorEvent {
  const RetryLoadSalesInvoice();
}

/// Updates the date under editor.
class UpdateInvoiceDate extends SalesInvoiceEditorEvent {
  final DateTime date;

  const UpdateInvoiceDate(this.date);

  @override
  List<Object?> get props => [date];
}

/// Updates the customer under editor.
class UpdateInvoiceCustomer extends SalesInvoiceEditorEvent {
  final Customer customer;

  const UpdateInvoiceCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// Adds or updates a line item on the active form.
class AddOrUpdateLineItem extends SalesInvoiceEditorEvent {
  final Item item;
  final double quantity;
  final double? rate;
  final double? discount;
  final String? uom;
  final String? unitConversionId;

  const AddOrUpdateLineItem({
    required this.item,
    required this.quantity,
    this.rate,
    this.discount,
    this.uom,
    this.unitConversionId,
  });

  @override
  List<Object?> get props =>
      [item, quantity, rate, discount, uom, unitConversionId];
}

/// Removes a line item.
class RemoveLineItem extends SalesInvoiceEditorEvent {
  final Item item;

  const RemoveLineItem(this.item);

  @override
  List<Object?> get props => [item];
}

/// Saves the current invoice form locally and enqueues sync.
class SaveInvoice extends SalesInvoiceEditorEvent {
  final String notes;

  const SaveInvoice({required this.notes});

  @override
  List<Object?> get props => [notes];
}

/// Clears editor error/success messages.
class ClearSalesInvoiceEditorMessages extends SalesInvoiceEditorEvent {
  const ClearSalesInvoiceEditorMessages();
}
