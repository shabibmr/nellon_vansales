import 'package:equatable/equatable.dart';
import '../../../../domain/models/customer.dart';

abstract class GpsCaptureState extends Equatable {
  const GpsCaptureState();

  @override
  List<Object?> get props => [];
}

class GpsCaptureIdle extends GpsCaptureState {}

class GpsCaptureInProgress extends GpsCaptureState {}

class GpsCaptureSuccess extends GpsCaptureState {
  final double latitude;
  final double longitude;
  final Customer? enrichedCustomer;

  const GpsCaptureSuccess({
    required this.latitude,
    required this.longitude,
    this.enrichedCustomer,
  });

  @override
  List<Object?> get props => [latitude, longitude, enrichedCustomer];
}

class GpsCapturePermissionDenied extends GpsCaptureState {}

class GpsCaptureServiceDisabled extends GpsCaptureState {}

class GpsCaptureFailure extends GpsCaptureState {
  final String message;

  const GpsCaptureFailure(this.message);

  @override
  List<Object?> get props => [message];
}
