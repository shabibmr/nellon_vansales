import 'package:equatable/equatable.dart';
import '../../../../domain/models/cash_closing.dart';

abstract class CashClosingState extends Equatable {
  const CashClosingState();

  @override
  List<Object?> get props => [];
}

class CashClosingInitial extends CashClosingState {}

class CashClosingSubmitting extends CashClosingState {}

class CashClosingSuccess extends CashClosingState {
  final CashClosing closing;

  const CashClosingSuccess(this.closing);

  @override
  List<Object?> get props => [closing];
}

class CashClosingFailure extends CashClosingState {
  final String message;

  const CashClosingFailure(this.message);

  @override
  List<Object?> get props => [message];
}
