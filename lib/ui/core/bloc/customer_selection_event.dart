import 'package:equatable/equatable.dart';
import '../../../domain/models/customer.dart';

abstract class CustomerSelectionEvent extends Equatable {
  const CustomerSelectionEvent();

  @override
  List<Object?> get props => [];
}

/// A row in the selector list was tapped — resolve its details and decide
/// whether the missing-fields dialog is needed.
class CustomerTapped extends CustomerSelectionEvent {
  final Customer customer;

  const CustomerTapped(this.customer);

  @override
  List<Object?> get props => [customer];
}

/// The missing-fields dialog closed (saved, skipped, or dismissed) — always
/// carries a customer, since dismissal now just proceeds with what was
/// already selected.
class MissingFieldsResolved extends CustomerSelectionEvent {
  final Customer customer;

  const MissingFieldsResolved(this.customer);

  @override
  List<Object?> get props => [customer];
}
