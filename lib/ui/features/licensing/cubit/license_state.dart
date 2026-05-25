import 'package:equatable/equatable.dart';
import '../../../../domain/models/server_config.dart';

/// Base class for all states emitted by the [LicenseCubit].
abstract class LicenseState extends Equatable {
  const LicenseState();

  @override
  List<Object?> get props => [];
}

/// Initial state when licensing checks have not started.
class LicenseInitial extends LicenseState {}

/// State representing an active license check/validation in progress.
class LicenseChecking extends LicenseState {}

/// State indicating a valid license.
class LicenseValid extends LicenseState {
  /// The Zoho integration server configuration (if loaded).
  final ServerConfig? serverConfig;

  const LicenseValid({this.serverConfig});

  @override
  List<Object?> get props => [serverConfig];
}

/// State emitted when the device has no registered license UUID, requiring initial registration.
class LicensePendingFirstLogin extends LicenseState {}

/// State indicating the license is invalid, expired, or manually disabled.
class LicenseBlocked extends LicenseState {
  final String reason;

  const LicenseBlocked({required this.reason});

  @override
  List<Object?> get props => [reason];
}

/// State representing a network error or fetch failure during verification (when fail-closed).
class LicenseError extends LicenseState {
  final String message;

  const LicenseError(this.message);

  @override
  List<Object?> get props => [message];
}
