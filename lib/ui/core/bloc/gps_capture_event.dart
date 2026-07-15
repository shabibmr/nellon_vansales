import 'package:equatable/equatable.dart';
import '../../../../domain/models/customer.dart';

abstract class GpsCaptureEvent extends Equatable {
  const GpsCaptureEvent();

  @override
  List<Object?> get props => [];
}

class GpsCaptureRequested extends GpsCaptureEvent {
  final Customer? customer;
  final bool persist;

  const GpsCaptureRequested({this.customer, required this.persist});

  @override
  List<Object?> get props => [customer, persist];
}
