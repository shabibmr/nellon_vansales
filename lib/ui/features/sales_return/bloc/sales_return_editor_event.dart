import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_return.dart';

/// Base class for events handled by [SalesReturnEditorBloc].
abstract class SalesReturnEditorEvent extends Equatable {
  const SalesReturnEditorEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a blank form for a new sales return.
class StartNewReturn extends SalesReturnEditorEvent {
  final Customer? customer;

  const StartNewReturn({this.customer});

  @override
  List<Object?> get props => [customer];
}

/// Opens an existing sales return.
class OpenSalesReturn extends SalesReturnEditorEvent {
  final SalesReturn salesReturn;

  const OpenSalesReturn(this.salesReturn);

  @override
  List<Object?> get props => [salesReturn];
}

/// Re-attempts remote fetch for the return held in editor state.
class RetryLoadSalesReturn extends SalesReturnEditorEvent {
  const RetryLoadSalesReturn();
}

/// Re-fetches a synced sales return from Zoho and updates the form if it changed.
///
/// [forceDirty] covers controller-only reason edits not yet in BLoC state.
class RefreshSalesReturnFromZoho extends SalesReturnEditorEvent {
  final bool forceDirty;

  const RefreshSalesReturnFromZoho({this.forceDirty = false});

  @override
  List<Object?> get props => [forceDirty];
}

/// Mirrors return reason text into BLoC state (dirty tracking).
class UpdateReturnReason extends SalesReturnEditorEvent {
  final String reason;

  const UpdateReturnReason(this.reason);

  @override
  List<Object?> get props => [reason];
}

/// Updates return date.
class UpdateReturnDate extends SalesReturnEditorEvent {
  final DateTime date;

  const UpdateReturnDate(this.date);

  @override
  List<Object?> get props => [date];
}

/// Updates return customer.
class UpdateReturnCustomer extends SalesReturnEditorEvent {
  final Customer customer;

  const UpdateReturnCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// Adds or updates a return line item.
class AddOrUpdateReturnLineItem extends SalesReturnEditorEvent {
  final Item item;
  final double quantity;

  const AddOrUpdateReturnLineItem({
    required this.item,
    required this.quantity,
  });

  @override
  List<Object?> get props => [item, quantity];
}

/// Sets specific return line items for a product.
class SetReturnLineItemsForProduct extends SalesReturnEditorEvent {
  final Item item;
  final List<SalesReturnLineItem> lines;

  const SetReturnLineItemsForProduct({
    required this.item,
    required this.lines,
  });

  @override
  List<Object?> get props => [item, lines];
}

/// Removes a return line item.
class RemoveReturnLineItem extends SalesReturnEditorEvent {
  final Item item;

  const RemoveReturnLineItem(this.item);

  @override
  List<Object?> get props => [item];
}

/// Saves the sales return.
class SaveReturn extends SalesReturnEditorEvent {
  final String reason;

  const SaveReturn({required this.reason});

  @override
  List<Object?> get props => [reason];
}

/// Clears editor error/success messages.
class ClearSalesReturnEditorMessages extends SalesReturnEditorEvent {
  const ClearSalesReturnEditorMessages();
}
