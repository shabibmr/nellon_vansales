import '../../domain/models/server_config.dart';
import '../../domain/repositories/server_config_repository.dart';
import '../services/app_logger.dart';
import '../services/debug_file_logger.dart';
import '../services/error_classification.dart';
import '../services/license_service.dart';
import '../services/local_storage_service.dart';
import '../services/zoho_api_client.dart';

/// Resolves Zoho credentials from Firestore `server_config/zoho` first, then
/// falls back to what [ZohoApiClient] already holds and the secure-storage
/// cache (offline / incomplete remote).
class ServerConfigRepositoryImpl implements ServerConfigRepository {
  final ZohoApiClient _apiClient;
  final LocalStorageService _localStorage;
  final LicenseService _licenseService;

  ServerConfigRepositoryImpl({
    required ZohoApiClient apiClient,
    required LocalStorageService localStorage,
    required LicenseService licenseService,
  }) : _apiClient = apiClient,
       _localStorage = localStorage,
       _licenseService = licenseService;

  @override
  bool get hasCredentials => _apiClient.hasCredentials;

  @override
  Future<bool> ensureCredentialsLoaded() async {
    try {
      DebugFileLogger.log(
        '[ServerConfigRepository] 🌐 Fetching server configuration from remote Firestore...',
      );
      final remote = await _licenseService.fetchServerConfig();
      if (_isComplete(remote)) {
        DebugFileLogger.log(
          '[ServerConfigRepository] 📥 Remote config loaded: '
          'clientId="${remote.clientId}", clientSecret="${remote.clientSecret}", '
          'code="${remote.code}", orgId="${remote.organizationId}"',
        );
        _apply(remote);
        await _localStorage.saveZohoCredentials(remote);
        AppLogger.info(
          'ServerConfig',
          'Applied Zoho credentials from Firestore '
          'clientId="${remote.clientId}" orgId="${remote.organizationId}"',
        );
        return true;
      }

      DebugFileLogger.log(
        '[ServerConfigRepository] ⚠️ Firestore server_config/zoho is incomplete. '
        'clientId=${remote.clientId.isNotEmpty ? "[SET]" : "[EMPTY]"}, '
        'clientSecret=${remote.clientSecret.isNotEmpty ? "[SET]" : "[EMPTY]"}, '
        'code/refreshToken=${remote.code.isNotEmpty ? "[SET]" : "[EMPTY]"}',
      );
      AppLogger.warning(
        'ServerConfig',
        'Firestore server_config/zoho is incomplete; keeping cached credentials. '
        'clientId=${remote.clientId.isNotEmpty ? "[SET]" : "[EMPTY]"}, '
        'clientSecret=${remote.clientSecret.isNotEmpty ? "[SET]" : "[EMPTY]"}, '
        'code/refreshToken=${remote.code.isNotEmpty ? "[SET]" : "[EMPTY]"}',
      );
    } catch (e) {
      DebugFileLogger.log(
        '[ServerConfigRepository] ❌ Remote config fetch failed: $e',
      );
      if (isFirestorePermissionDenied(e)) {
        AppLogger.error(
          'ServerConfig',
          'Firestore permission-denied reading server_config/zoho.',
        );
      } else {
        AppLogger.warning('ServerConfig', 'Remote config fetch failed: $e');
      }
    }

    if (_apiClient.hasCredentials) {
      DebugFileLogger.log(
        '[ServerConfigRepository] ⚡ Using in-memory Zoho credentials after remote miss.',
      );
      return true;
    }

    try {
      final cached = await _localStorage.readZohoCredentials();
      if (cached != null && _isComplete(cached)) {
        DebugFileLogger.log(
          '[ServerConfigRepository] 📂 Loaded credentials from local secure cache: '
          'clientId="${cached.clientId}", clientSecret="${cached.clientSecret}", '
          'code="${cached.code}", orgId="${cached.organizationId}"',
        );
        _apply(cached);
      }
    } catch (e) {
      DebugFileLogger.log(
        '[ServerConfigRepository] ⚠️ Secure-cache credential read failed: $e',
      );
      AppLogger.warning('ServerConfig', 'Secure-cache credential read failed: $e');
    }

    return _apiClient.hasCredentials;
  }

  void _apply(ServerConfig config) {
    _apiClient.updateCredentials(
      clientId: config.clientId,
      clientSecret: config.clientSecret,
      refreshToken: config.code,
      organizationId: config.organizationId,
    );
  }

  /// [ZohoApiClient.updateCredentials] silently ignores a partial triple, so
  /// completeness is checked before calling it rather than after.
  bool _isComplete(ServerConfig config) =>
      config.clientId.trim().isNotEmpty &&
      config.clientSecret.trim().isNotEmpty &&
      config.code.trim().isNotEmpty;
}
