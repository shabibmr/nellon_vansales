import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/models/customer.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import 'create_customer_state.dart';

class CreateCustomerCubit extends Cubit<CreateCustomerState> {
  final SalesRepository salesRepository;

  CreateCustomerCubit({required this.salesRepository}) : super(CreateCustomerInitial());

  Future<void> submit({
    required String name,
    required String company,
    required String email,
    required String phone,
    required String address,
    required double creditLimit,
    required String activeRouteId,
    double? latitude,
    double? longitude,
  }) async {
    if (state is CreateCustomerSaving) return;
    emit(CreateCustomerSaving());

    try {
      final localCustomers = salesRepository.getCustomers();
      final tempId = 'temp_cust_${DateTime.now().millisecondsSinceEpoch}';

      final newCustomer = Customer(
        id: tempId,
        name: name,
        companyName: company,
        email: email,
        phone: phone,
        address: address,
        outstandingBalance: 0.0,
        creditLimit: creditLimit,
        routeId: activeRouteId,
        sequence: localCustomers.length + 1,
        latitude: latitude,
        longitude: longitude,
        isPendingSync: true,
      );

      // 1. Persist locally via repository
      await salesRepository.saveCustomers([...localCustomers, newCustomer]);

      // 2. Build Zoho payload
      final customerPayload = <String, dynamic>{
        'contact_name': name,
        'company_name': company,
        'email': email,
        'phone': phone,
        'billing_address': {'address': address},
        'route_id': activeRouteId,
        'credit_limit': creditLimit,
        'isPendingSync': true,
      };

      if (latitude != null && longitude != null) {
        customerPayload['custom_fields'] = [
          {'api_name': 'cf_latitude', 'value': latitude.toString()},
          {'api_name': 'cf_longitude', 'value': longitude.toString()},
        ];
      }

      // 3. Enqueue for Zoho sync
      final syncItem = SyncQueueItem(
        id: tempId,
        type: 'customer',
        payload: customerPayload,
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      );
      await salesRepository.enqueueSyncItem(syncItem);

      emit(CreateCustomerSuccess(newCustomer));
    } catch (e) {
      emit(CreateCustomerFailure(e.toString()));
    }
  }
}
