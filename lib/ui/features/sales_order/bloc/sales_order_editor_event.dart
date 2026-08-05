import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/item.dart';
import '../../../../domain/models/sales_order.dart';

/// Base class for events handled by [SalesOrderEditorBloc].
abstract class SalesOrderEditorEvent extends Equatable {
  const SalesOrderEditorEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a blank form for a new sales order.
///
/// Optional [customer] prefills the form (e.g. dashboard customer flow).
class StartNewSalesOrder extends SalesOrderEditorEvent {
  final Customer? customer;

  const StartNewSalesOrder({this.customer});

  @override
  List<Object?> get props => [customer];
}

/// Opens an existing order. Saved orders are re-read from Zoho; pending-local
/// orders open from the provided [order] snapshot.
class OpenSalesOrder extends SalesOrderEditorEvent {
  final SalesOrder order;

  const OpenSalesOrder(this.order);

  @override
  List<Object?> get props => [order];
}

/// Re-attempts the Zoho fetch for the order held in editor state.
class RetryLoadSalesOrder extends SalesOrderEditorEvent {
  const RetryLoadSalesOrder();
}

/// Re-fetches a synced sales order from Zoho and updates the form if it changed.
///
/// [forceDirty] covers controller-only notes edits not yet in BLoC state.
class RefreshSalesOrderFromZoho extends SalesOrderEditorEvent {
  final bool forceDirty;

  const RefreshSalesOrderFromZoho({this.forceDirty = false});

  @override
  List<Object?> get props => [forceDirty];
}

/// Mirrors notes text from the editor field into BLoC state (dirty tracking).
class UpdateOrderNotes extends SalesOrderEditorEvent {
  final String notes;

  const UpdateOrderNotes(this.notes);

  @override
  List<Object?> get props => [notes];
}

/// Updates the expected shipment date under the editor.
class UpdateOrderShipmentDate extends SalesOrderEditorEvent {
  final DateTime shipmentDate;

  const UpdateOrderShipmentDate(this.shipmentDate);

  @override
  List<Object?> get props => [shipmentDate];
}

/// Updates the customer under the editor.
class UpdateOrderCustomer extends SalesOrderEditorEvent {
  final Customer customer;

  const UpdateOrderCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// Adds or updates a line item on the active form.
class AddOrUpdateOrderLine extends SalesOrderEditorEvent {
  final Item item;
  final double quantity;
  final double? rate;
  final double? discount;
  final String? uom;
  final String? unitConversionId;

  const AddOrUpdateOrderLine({
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

/// Removes a line item by product.
class RemoveOrderLine extends SalesOrderEditorEvent {
  final Item item;

  const RemoveOrderLine(this.item);

  @override
  List<Object?> get props => [item];
}

/// Saves the current form locally and enqueues sync.
class SaveSalesOrder extends SalesOrderEditorEvent {
  final String notes;

  const SaveSalesOrder({required this.notes});

  @override
  List<Object?> get props => [notes];
}

/// Clears editor error/success snackbar messages.
class ClearSalesOrderEditorMessages extends SalesOrderEditorEvent {
  const ClearSalesOrderEditorMessages();
}
