import 'package:equatable/equatable.dart';
import '../../../../domain/models/customer.dart';

abstract class CreateCustomerState extends Equatable {
  const CreateCustomerState();

  @override
  List<Object?> get props => [];
}

class CreateCustomerInitial extends CreateCustomerState {}

class CreateCustomerSaving extends CreateCustomerState {}

class CreateCustomerSuccess extends CreateCustomerState {
  final Customer customer;

  const CreateCustomerSuccess(this.customer);

  @override
  List<Object?> get props => [customer];
}

class CreateCustomerFailure extends CreateCustomerState {
  final String message;

  const CreateCustomerFailure(this.message);

  @override
  List<Object?> get props => [message];
}
