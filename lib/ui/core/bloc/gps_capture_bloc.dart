import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../domain/repositories/sales_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../data/services/zoho_api_client.dart';
import 'gps_capture_event.dart';
import 'gps_capture_state.dart';

class GpsCaptureBloc extends Bloc<GpsCaptureEvent, GpsCaptureState> {
  final SalesRepository salesRepository;
  final ZohoApiClient zohoApiClient;
  final SyncWorker syncWorker;

  GpsCaptureBloc({
    required this.salesRepository,
    required this.zohoApiClient,
    required this.syncWorker,
  }) : super(GpsCaptureIdle()) {
    on<GpsCaptureRequested>(_onGpsCaptureRequested);
  }

  Future<void> _onGpsCaptureRequested(
    GpsCaptureRequested event,
    Emitter<GpsCaptureState> emit,
  ) async {
    if (state is GpsCaptureInProgress) return;
    emit(GpsCaptureInProgress());

    try {
      // 1. Check/request permission
      var status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        status = await Permission.locationWhenInUse.request();
      }
      if (!status.isGranted) {
        emit(GpsCapturePermissionDenied());
        return;
      }

      // 2. Check if service is enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        emit(GpsCaptureServiceDisabled());
        return;
      }

      // 3. Get current location (12 seconds timeout)
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );

      final lat = pos.latitude;
      final lng = pos.longitude;

      if (event.persist) {
        final customer = event.customer;
        if (customer == null) {
          emit(const GpsCaptureFailure('Customer is required for persist mode.'));
          return;
        }

        // A. Update local cache immediately
        await salesRepository.updateCustomerGps(customer.id, lat, lng);

        // B. Immediate Zoho update (best effort). Falls back to queue if it fails or if temp_ id.
        bool remoteUpdated = false;
        if (customer.id.isNotEmpty && !customer.id.startsWith('temp_')) {
          try {
            await zohoApiClient.updateCustomerGps(customer.id, lat, lng);
            remoteUpdated = true;
          } catch (_) {
            // Zoho failure is swallowed, fall back to sync queue
          }
        }

        // C. Enqueue fallback + kick sync if remote didn't succeed right now
        if (!remoteUpdated) {
          final queueItem = SyncQueueItem(
            id: 'gps_${customer.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: 'customer_gps_update',
            payload: {
              'contact_id': customer.id,
              'latitude': lat,
              'longitude': lng,
            },
            status: SyncStatus.pending,
            timestamp: DateTime.now(),
          );
          await salesRepository.enqueueSyncItem(queueItem);
          syncWorker.syncPendingItems();
        }

        final enrichedCustomer = customer.copyWith(latitude: lat, longitude: lng);
        emit(GpsCaptureSuccess(
          latitude: lat,
          longitude: lng,
          enrichedCustomer: enrichedCustomer,
        ));
      } else {
        // Capture-only mode: just return lat/lng
        emit(GpsCaptureSuccess(latitude: lat, longitude: lng));
      }
    } catch (e) {
      emit(GpsCaptureFailure(e.toString()));
    }
  }
}
