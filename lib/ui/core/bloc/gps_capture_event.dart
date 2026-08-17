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

class ContactFieldsSaveRequested extends GpsCaptureEvent {
  final Customer customer;
  final String? phone;
  final String? trn;

  const ContactFieldsSaveRequested({
    required this.customer,
    this.phone,
    this.trn,
  });

  @override
  List<Object?> get props => [customer, phone, trn];
}
