import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/server_config.dart';
import 'server_config_state.dart';

/// Cubit managing app-wide server integration settings.
///
/// Ensures active Zoho OAuth configurations are propagated app-wide and injected into
/// [ZohoApiClient] dynamically on verified licensing login.
class ServerConfigCubit extends Cubit<ServerConfigState> {
  final ZohoApiClient _apiClient;

  ServerConfigCubit({required ZohoApiClient apiClient})
      : _apiClient = apiClient,
        super(ServerConfigInitial());

  /// Configures the active server credentials mapping, updating [ZohoApiClient].
  void setConfig(ServerConfig? config) {
    if (config == null) {
      emit(ServerConfigInitial());
      return;
    }

    try {
      // Feed ZohoApiClient with the freshly resolved credentials
      _apiClient.updateCredentials(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        refreshToken: config.code,
      );

      emit(ServerConfigLoaded(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        code: config.code,
      ));
    } catch (e) {
      emit(ServerConfigError('Failed to inject server configuration credentials: $e'));
    }
  }

  /// Resets server configurations to initial unconfigured states.
  void reset() {
    emit(ServerConfigInitial());
  }
}
