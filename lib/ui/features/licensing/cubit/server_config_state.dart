import 'package:equatable/equatable.dart';

/// Base class representing all states for Zoho integration credentials mapping.
abstract class ServerConfigState extends Equatable {
  const ServerConfigState();

  /// Whether transaction uploads are simulated instead of pushed live.
  bool get isMockModeEnabled;

  @override
  List<Object?> get props => [isMockModeEnabled];
}

/// Initial state indicating no server credentials have been successfully resolved.
class ServerConfigInitial extends ServerConfigState {
  @override
  final bool isMockModeEnabled;

  const ServerConfigInitial({required this.isMockModeEnabled});

  @override
  List<Object?> get props => [isMockModeEnabled];
}

/// State containing verified active server configurations.
class ServerConfigLoaded extends ServerConfigState {
  final String clientId;
  final String clientSecret;
  final String code;

  @override
  final bool isMockModeEnabled;

  const ServerConfigLoaded({
    required this.clientId,
    required this.clientSecret,
    required this.code,
    required this.isMockModeEnabled,
  });

  @override
  List<Object?> get props => [
    clientId,
    clientSecret,
    code,
    isMockModeEnabled,
  ];
}

/// State emitted if server configurations map incorrectly.
class ServerConfigError extends ServerConfigState {
  final String message;

  @override
  final bool isMockModeEnabled;

  const ServerConfigError(this.message, {required this.isMockModeEnabled});

  @override
  List<Object?> get props => [message, isMockModeEnabled];
}