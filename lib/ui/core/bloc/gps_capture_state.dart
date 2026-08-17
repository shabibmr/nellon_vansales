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
  final double? accuracy;
  final Customer? enrichedCustomer;

  const GpsCaptureSuccess({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.enrichedCustomer,
  });

  @override
  List<Object?> get props => [latitude, longitude, accuracy, enrichedCustomer];
}

/// The device produced a fix, but it's too imprecise to trust — caller
/// should prompt the user to retry rather than silently persisting it.
class GpsCaptureInaccurate extends GpsCaptureState {
  final double accuracy;

  const GpsCaptureInaccurate(this.accuracy);

  @override
  List<Object?> get props => [accuracy];
}

class GpsCapturePermissionDenied extends GpsCaptureState {
  /// True when the OS will not show the system permission sheet again
  /// (user must open app settings).
  final bool permanentlyDenied;

  const GpsCapturePermissionDenied({this.permanentlyDenied = false});

  @override
  List<Object?> get props => [permanentlyDenied];
}

class GpsCaptureServiceDisabled extends GpsCaptureState {}

class GpsCaptureFailure extends GpsCaptureState {
  final String message;

  const GpsCaptureFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class ContactFieldsSaveInProgress extends GpsCaptureState {}

class ContactFieldsSaved extends GpsCaptureState {
  final Customer enrichedCustomer;

  const ContactFieldsSaved(this.enrichedCustomer);

  @override
  List<Object?> get props => [enrichedCustomer];
}

class ContactFieldsSaveFailure extends GpsCaptureState {
  final String message;

  const ContactFieldsSaveFailure(this.message);

  @override
  List<Object?> get props => [message];
}
