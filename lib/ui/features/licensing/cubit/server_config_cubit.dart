import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/hive_database_service.dart';
import '../../../../data/services/zoho_api_client.dart';
import '../../../../domain/models/server_config.dart';
import 'server_config_state.dart';

/// Cubit managing app-wide server integration settings.
///
/// Ensures active Zoho OAuth configurations are propagated app-wide and injected into
/// [ZohoApiClient] dynamically on verified licensing login.
class ServerConfigCubit extends Cubit<ServerConfigState> {
  final ZohoApiClient _apiClient;
  final HiveDatabaseService _dbService;

  ServerConfigCubit({
    required ZohoApiClient apiClient,
    required HiveDatabaseService dbService,
  }) : _apiClient = apiClient,
       _dbService = dbService,
       super(
         ServerConfigInitial(
           isMockModeEnabled: _bootstrapMockMode(dbService, apiClient),
         ),
       );

  static bool _bootstrapMockMode(
    HiveDatabaseService dbService,
    ZohoApiClient apiClient,
  ) {
    final persisted = dbService.transactionMockModeEnabled;
    final enabled = persisted ?? true;
    apiClient.setAllMockFlags(enabled);
    return enabled;
  }

  /// Configures the active server credentials mapping, updating [ZohoApiClient].
  void setConfig(ServerConfig? config) {
    if (config == null) {
      emit(ServerConfigInitial(isMockModeEnabled: _apiClient.isMockModeEnabled));
      return;
    }

    // An incomplete Firestore doc (empty client_id/client_secret/code) must
    // not wipe the client's current working credentials — empty strings pass
    // the placeholder check and leave the app "live" but unable to
    // authenticate, so every master fetch dies with a silent 401.
    if (config.clientId.isEmpty ||
        config.clientSecret.isEmpty ||
        config.code.isEmpty) {
      emit(
        ServerConfigError(
          'Server configuration is incomplete (empty Zoho credentials in '
          'server_config/zoho). Keeping previously configured credentials.',
          isMockModeEnabled: _apiClient.isMockModeEnabled,
        ),
      );
      return;
    }

    try {
      _apiClient.updateCredentials(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        refreshToken: config.code,
        organizationId: config.organizationId,
      );

      final mockEnabled = _resolveMockMode(config);
      _apiClient.setAllMockFlags(mockEnabled);

      emit(
        ServerConfigLoaded(
          clientId: config.clientId,
          clientSecret: config.clientSecret,
          code: config.code,
          isMockModeEnabled: mockEnabled,
        ),
      );
    } catch (e) {
      emit(
        ServerConfigError(
          'Failed to inject server configuration credentials: $e',
          isMockModeEnabled: _apiClient.isMockModeEnabled,
        ),
      );
    }
  }

  /// Toggles all transaction mock flags together and persists the preference.
  Future<void> setMockModeEnabled(bool enabled) async {
    await _dbService.setTransactionMockModeEnabled(enabled);
    _apiClient.setAllMockFlags(enabled);

    final current = state;
    switch (current) {
      case ServerConfigLoaded():
        emit(
          ServerConfigLoaded(
            clientId: current.clientId,
            clientSecret: current.clientSecret,
            code: current.code,
            isMockModeEnabled: enabled,
          ),
        );
      case ServerConfigError():
        emit(
          ServerConfigError(
            current.message,
            isMockModeEnabled: enabled,
          ),
        );
      case ServerConfigInitial():
        emit(ServerConfigInitial(isMockModeEnabled: enabled));
    }
  }

  bool _resolveMockMode(ServerConfig config) {
    final persisted = _dbService.transactionMockModeEnabled;
    if (persisted != null) return persisted;

    return config.mockTransactions ||
        config.mockSalesOrderTransactions ||
        config.mockStockTransfers;
  }

  /// Resets server configurations to initial unconfigured states.
  void reset() {
    emit(
      ServerConfigInitial(isMockModeEnabled: _apiClient.isMockModeEnabled),
    );
  }
}