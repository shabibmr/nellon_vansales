import 'package:equatable/equatable.dart';

/// Base class representing all states for Zoho integration credentials mapping.
abstract class ServerConfigState extends Equatable {
  const ServerConfigState();

  @override
  List<Object?> get props => [];
}

/// Initial state indicating no server credentials have been successfully resolved.
class ServerConfigInitial extends ServerConfigState {}

/// State containing verified active server configurations.
class ServerConfigLoaded extends ServerConfigState {
  final String clientId;
  final String clientSecret;
  final String code;

  const ServerConfigLoaded({
    required this.clientId,
    required this.clientSecret,
    required this.code,
  });

  @override
  List<Object?> get props => [clientId, clientSecret, code];
}

/// State emitted if server configurations map incorrectly.
class ServerConfigError extends ServerConfigState {
  final String message;

  const ServerConfigError(this.message);

  @override
  List<Object?> get props => [message];
}
