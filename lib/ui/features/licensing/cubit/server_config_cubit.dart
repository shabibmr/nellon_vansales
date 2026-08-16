import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/local_storage_service.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/server_config.dart';
import '../../../core/utils/error_mapper.dart';
import 'server_config_state.dart';

/// Cubit managing app-wide server integration settings.
///
/// Injects Zoho OAuth credentials into [ZohoApiClient] from Firestore
/// `server_config/zoho` (via [setConfig]) and from the last-good secure cache
/// (via [_hydrate] on construct).
class ServerConfigCubit extends Cubit<ServerConfigState> {
  final ZohoApiClient apiClient;
  final LocalStorageService localStorage;

  /// Completes when the constructor cache hydrate finishes. Tests await this.
  late final Future<void> hydrateDone;

  ServerConfigCubit({
    required this.apiClient,
    required this.localStorage,
  }) : super(const ServerConfigInitial()) {
    hydrateDone = _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final cached = await localStorage.readZohoCredentials();
      if (isClosed) return;
      // Remote [setConfig] already won the race — do not overwrite it.
      if (state is ServerConfigLoaded) return;
      if (cached == null) return;

      apiClient.updateCredentials(
        clientId: cached.clientId,
        clientSecret: cached.clientSecret,
        refreshToken: cached.code,
        organizationId: cached.organizationId,
      );

      if (isClosed) return;
      if (state is ServerConfigLoaded) return;

      emit(
        ServerConfigLoaded(
          clientId: cached.clientId,
          clientSecret: cached.clientSecret,
          code: cached.code,
        ),
      );
    } catch (_) {
      // Stay Initial; a later remote setConfig can still inject.
    }
  }

  /// Configures the active server credentials mapping, updating [ZohoApiClient].
  void setConfig(ServerConfig? config) {
    if (config == null) {
      emit(const ServerConfigInitial());
      return;
    }

    // An incomplete Firestore doc (empty client_id/client_secret/code) must
    // not wipe the client's current working credentials — empty strings pass
    // through and leave the app unable to authenticate.
    if (config.clientId.isEmpty ||
        config.clientSecret.isEmpty ||
        config.code.isEmpty) {
      emit(
        const ServerConfigError(
          'Server configuration is incomplete (empty Zoho credentials in '
          'server_config/zoho). Keeping previously configured credentials.',
        ),
      );
      return;
    }

    try {
      apiClient.updateCredentials(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        refreshToken: config.code,
        organizationId: config.organizationId,
      );

      unawaited(localStorage.saveZohoCredentials(config));

      emit(
        ServerConfigLoaded(
          clientId: config.clientId,
          clientSecret: config.clientSecret,
          code: config.code,
        ),
      );
    } catch (e) {
      emit(
        ServerConfigError(
          'Failed to inject server configuration credentials: ${userFacingMessage(e)}',
        ),
      );
    }
  }

  /// Resets server configurations to initial unconfigured states.
  void reset() {
    emit(const ServerConfigInitial());
  }
}
