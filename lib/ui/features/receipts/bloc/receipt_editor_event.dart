import 'package:equatable/equatable.dart';

import '../../../../domain/models/customer.dart';
import '../../../../domain/models/receipt_voucher.dart';

/// Base class for events handled by [ReceiptEditorBloc].
abstract class ReceiptEditorEvent extends Equatable {
  const ReceiptEditorEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a blank form for a new receipt voucher.
class StartNewReceipt extends ReceiptEditorEvent {
  final Customer? customer;

  const StartNewReceipt({this.customer});

  @override
  List<Object?> get props => [customer];
}

/// Opens an existing receipt voucher.
class OpenReceiptVoucher extends ReceiptEditorEvent {
  final ReceiptVoucher receipt;

  const OpenReceiptVoucher(this.receipt);

  @override
  List<Object?> get props => [receipt];
}

/// Re-attempts remote fetch for the receipt held in editor state.
class RetryLoadReceiptVoucher extends ReceiptEditorEvent {
  const RetryLoadReceiptVoucher();
}

/// Re-fetches a synced receipt from Zoho and updates the form if it changed.
class RefreshReceiptVoucherFromZoho extends ReceiptEditorEvent {
  const RefreshReceiptVoucherFromZoho();
}

/// Updates the customer under editor.
class SetEditingReceiptCustomer extends ReceiptEditorEvent {
  final Customer customer;

  const SetEditingReceiptCustomer(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// Updates payment amount.
class SetEditingAmount extends ReceiptEditorEvent {
  final double amount;

  const SetEditingAmount(this.amount);

  @override
  List<Object?> get props => [amount];
}

/// Updates payment mode.
class SetEditingPaymentMode extends ReceiptEditorEvent {
  final String mode;

  const SetEditingPaymentMode(this.mode);

  @override
  List<Object?> get props => [mode];
}

/// Updates reference number.
class SetEditingReference extends ReceiptEditorEvent {
  final String reference;

  const SetEditingReference(this.reference);

  @override
  List<Object?> get props => [reference];
}

/// Updates receipt date.
class SetEditingReceiptDate extends ReceiptEditorEvent {
  final DateTime date;

  const SetEditingReceiptDate(this.date);

  @override
  List<Object?> get props => [date];
}

/// Updates payment allocations.
class UpdateReceiptAllocations extends ReceiptEditorEvent {
  final List<PaymentAllocation> allocations;

  const UpdateReceiptAllocations(this.allocations);

  @override
  List<Object?> get props => [allocations];
}

/// Saves the receipt voucher.
class SaveReceipt extends ReceiptEditorEvent {
  const SaveReceipt();
}

/// Clears editor error/success messages.
class ClearReceiptEditorMessages extends ReceiptEditorEvent {
  const ClearReceiptEditorMessages();
}
