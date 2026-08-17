import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../domain/repositories/customer_repository.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';
import '../utils/error_mapper.dart';
import 'gps_capture_event.dart';
import 'gps_capture_state.dart';

/// GPS fixes worse than this (meters) are rejected rather than persisted.
const double kMaxAcceptableGpsAccuracyMeters = 50.0;

class GpsCaptureBloc extends Bloc<GpsCaptureEvent, GpsCaptureState> {
  final CustomerRepository customerRepository;
  final SyncRepository syncRepository;

  GpsCaptureBloc({
    required this.customerRepository,
    required this.syncRepository,
  }) : super(GpsCaptureIdle()) {
    on<GpsCaptureRequested>(_onGpsCaptureRequested);
    on<ContactFieldsSaveRequested>(_onContactFieldsSaveRequested);
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
      if (!status.isGranted && !status.isLimited) {
        status = await Permission.locationWhenInUse.request();
      }
      if (!status.isGranted && !status.isLimited) {
        emit(
          GpsCapturePermissionDenied(
            permanentlyDenied: status.isPermanentlyDenied,
          ),
        );
        return;
      }

      // 2. Check if service is enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        emit(GpsCaptureServiceDisabled());
        return;
      }

      // 3. Get current location (12 seconds timeout)
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final lat = pos.latitude;
      final lng = pos.longitude;
      final accuracy = pos.accuracy;

      if (accuracy > kMaxAcceptableGpsAccuracyMeters) {
        emit(GpsCaptureInaccurate(accuracy));
        return;
      }

      if (event.persist) {
        final customer = event.customer;
        if (customer == null) {
          emit(
            const GpsCaptureFailure('Customer is required for persist mode.'),
          );
          return;
        }

        await customerRepository.submitOrEnqueue(
          SyncQueueItem(
            id: 'gps_${customer.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: 'customer_gps_update',
            payload: {
              'contact_id': customer.id,
              'latitude': lat,
              'longitude': lng,
            },
            status: SyncStatus.pending,
            timestamp: DateTime.now(),
          ),
        );

        final enrichedCustomer = customer.copyWith(
          latitude: lat,
          longitude: lng,
        );
        emit(
          GpsCaptureSuccess(
            latitude: lat,
            longitude: lng,
            accuracy: accuracy,
            enrichedCustomer: enrichedCustomer,
          ),
        );
      } else {
        // Capture-only mode: just return lat/lng
        emit(
          GpsCaptureSuccess(latitude: lat, longitude: lng, accuracy: accuracy),
        );
      }
    } catch (e) {
      emit(GpsCaptureFailure(userFacingMessage(e)));
    }
  }

  Future<void> _onContactFieldsSaveRequested(
    ContactFieldsSaveRequested event,
    Emitter<GpsCaptureState> emit,
  ) async {
    emit(ContactFieldsSaveInProgress());
    try {
      final customer = event.customer;
      await customerRepository.submitOrEnqueue(
        SyncQueueItem(
          id: 'contact_${customer.id}_${DateTime.now().millisecondsSinceEpoch}',
          type: 'customer_contact_update',
          payload: {
            'contact_id': customer.id,
            if (event.phone != null) 'phone': event.phone,
            if (event.trn != null) 'tax_reg_no': event.trn,
          },
          status: SyncStatus.pending,
          timestamp: DateTime.now(),
        ),
      );

      emit(
        ContactFieldsSaved(
          customer.copyWith(
            phone: event.phone ?? customer.phone,
            trn: event.trn ?? customer.trn,
          ),
        ),
      );
    } catch (e) {
      emit(ContactFieldsSaveFailure(userFacingMessage(e)));
    }
  }
}
