import 'package:equatable/equatable.dart';
import '../../../domain/models/customer.dart';

abstract class CustomerSelectionState extends Equatable {
  const CustomerSelectionState();

  @override
  List<Object?> get props => [];
}

class CustomerSelectionIdle extends CustomerSelectionState {}

class CustomerSelectionResolving extends CustomerSelectionState {
  final String customerId;

  const CustomerSelectionResolving(this.customerId);

  @override
  List<Object?> get props => [customerId];
}

/// Details resolved and the customer is still missing GPS/phone/TRN — the UI
/// should show the missing-fields dialog and report back via
/// [MissingFieldsResolved].
class CustomerSelectionNeedsMissingFields extends CustomerSelectionState {
  final Customer customer;
  final CustomerMissingFields missing;
  final bool offlineFallback;

  const CustomerSelectionNeedsMissingFields({
    required this.customer,
    required this.missing,
    this.offlineFallback = false,
  });

  @override
  List<Object?> get props => [customer, missing, offlineFallback];
}

/// Selection is final — the UI should invoke `onSelected` and close.
class CustomerSelectionCompleted extends CustomerSelectionState {
  final Customer customer;
  final bool offlineFallback;

  const CustomerSelectionCompleted({
    required this.customer,
    this.offlineFallback = false,
  });

  @override
  List<Object?> get props => [customer, offlineFallback];
}
