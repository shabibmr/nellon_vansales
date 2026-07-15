import 'package:equatable/equatable.dart';
import '../../../../domain/models/customer.dart';

abstract class ReceiptAllocationEvent extends Equatable {
  const ReceiptAllocationEvent();

  @override
  List<Object?> get props => [];
}

class ReceiptAllocationStarted extends ReceiptAllocationEvent {
  final Customer customer;

  const ReceiptAllocationStarted(this.customer);

  @override
  List<Object?> get props => [customer];
}

class OpenInvoicesRefreshRequested extends ReceiptAllocationEvent {}

class PaymentAmountChanged extends ReceiptAllocationEvent {
  final String rawAmount;

  const PaymentAmountChanged(this.rawAmount);

  @override
  List<Object?> get props => [rawAmount];
}

class PaymentModeChanged extends ReceiptAllocationEvent {
  final String mode;

  const PaymentModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

class InvoiceAllocationEdited extends ReceiptAllocationEvent {
  final String invoiceId;
  final String invoiceNumber;
  final String value;

  const InvoiceAllocationEdited({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.value,
  });

  @override
  List<Object?> get props => [invoiceId, invoiceNumber, value];
}

class ReceiptSubmitted extends ReceiptAllocationEvent {}
