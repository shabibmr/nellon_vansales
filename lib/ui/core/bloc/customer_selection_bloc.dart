import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/models/customer.dart';
import '../../../domain/repositories/customer_repository.dart';
import 'customer_selection_event.dart';
import 'customer_selection_state.dart';

/// Owns the tap-to-select flow for [CustomerSelectorSheet]: resolving a
/// tapped customer's details, deciding whether the missing-fields dialog is
/// needed, and finalizing the selection. Selection always completes — a
/// customer being missing GPS/phone/TRN, or the user dismissing that prompt,
/// never blocks it.
class CustomerSelectionBloc
    extends Bloc<CustomerSelectionEvent, CustomerSelectionState> {
  final CustomerRepository customerRepository;

  CustomerSelectionBloc({required this.customerRepository})
    : super(CustomerSelectionIdle()) {
    on<CustomerTapped>(_onCustomerTapped);
    on<MissingFieldsResolved>(_onMissingFieldsResolved);
  }

  Future<void> _onCustomerTapped(
    CustomerTapped event,
    Emitter<CustomerSelectionState> emit,
  ) async {
    emit(CustomerSelectionResolving(event.customer.id));

    final result = await customerRepository.resolveCustomerDetails(
      event.customer,
    );
    final resolved = result.customer;
    final missing = CustomerMissingFields.of(resolved);

    if (missing.any) {
      emit(
        CustomerSelectionNeedsMissingFields(
          customer: resolved,
          missing: missing,
          offlineFallback: result.offlineFallback,
        ),
      );
    } else {
      emit(
        CustomerSelectionCompleted(
          customer: resolved,
          offlineFallback: result.offlineFallback,
        ),
      );
    }
  }

  void _onMissingFieldsResolved(
    MissingFieldsResolved event,
    Emitter<CustomerSelectionState> emit,
  ) {
    emit(CustomerSelectionCompleted(customer: event.customer));
  }
}
