import '../../domain/models/server_config.dart';
import '../../domain/repositories/server_config_repository.dart';
import '../services/app_logger.dart';
import '../services/debug_file_logger.dart';
import '../services/error_classification.dart';
import '../services/license_service.dart';
import '../services/local_storage_service.dart';
import '../services/zoho_api_client.dart';

/// Resolves Zoho credentials from, in order: what [ZohoApiClient] already
/// holds, the secure-storage cache, then Firestore `server_config/zoho`.
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
    if (_apiClient.hasCredentials) {
      DebugFileLogger.log('[ServerConfigRepository] ⚡ ZohoApiClient already has active credentials.');
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
        _apiClient.updateCredentials(
          clientId: cached.clientId,
          clientSecret: cached.clientSecret,
          refreshToken: cached.code,
          organizationId: cached.organizationId,
        );
        if (_apiClient.hasCredentials) return true;
      }
    } catch (e) {
      DebugFileLogger.log('[ServerConfigRepository] ⚠️ Secure-cache credential read failed: $e');
      AppLogger.warning(
        'ServerConfig',
        'Secure-cache credential read failed: $e',
      );
    }

    try {
      DebugFileLogger.log('[ServerConfigRepository] 🌐 Fetching server configuration from remote Firestore...');
      final remote = await _licenseService.fetchServerConfig();
      if (!_isComplete(remote)) {
        DebugFileLogger.log(
          '[ServerConfigRepository] ⚠️ Firestore server_config/zoho is INCOMPLETE! '
          'clientId=${remote.clientId.isNotEmpty ? "[SET len=${remote.clientId.length}]" : "[EMPTY]"}, '
          'clientSecret=${remote.clientSecret.isNotEmpty ? "[SET len=${remote.clientSecret.length}]" : "[EMPTY]"}, '
          'code/refreshToken=${remote.code.isNotEmpty ? "[SET len=${remote.code.length}]" : "[EMPTY]"}',
        );
        AppLogger.warning(
          'ServerConfig',
          'Firestore server_config/zoho is incomplete. '
          'clientId=${remote.clientId.isNotEmpty ? "[SET]" : "[EMPTY]"}, '
          'clientSecret=${remote.clientSecret.isNotEmpty ? "[SET]" : "[EMPTY]"}, '
          'code/refreshToken=${remote.code.isNotEmpty ? "[SET]" : "[EMPTY]"}',
        );
        return false;
      }

      DebugFileLogger.log(
        '[ServerConfigRepository] 📥 Remote config loaded successfully: '
        'clientId="${remote.clientId}", '
        'clientSecret="${remote.clientSecret}", '
        'code="${remote.code}", '
        'orgId="${remote.organizationId}"',
      );

      _apiClient.updateCredentials(
        clientId: remote.clientId,
        clientSecret: remote.clientSecret,
        refreshToken: remote.code,
        organizationId: remote.organizationId,
      );
      // Cached so the next boot resolves without a Firestore round-trip.
      await _localStorage.saveZohoCredentials(remote);
      AppLogger.info(
        'ServerConfig',
        'Successfully loaded and cached Zoho credentials from Firestore.',
      );
    } catch (e) {
      DebugFileLogger.log('[ServerConfigRepository] ❌ Remote config fetch failed: $e');
      if (isFirestorePermissionDenied(e)) {
        AppLogger.error(
          'ServerConfig',
          'Firestore permission-denied reading server_config/zoho. '
          'Zoho OAuth will not be attempted with an empty token.',
        );
      } else {
        AppLogger.warning('ServerConfig', 'Remote config fetch failed: $e');
      }
    }

    return _apiClient.hasCredentials;
  }

  /// [ZohoApiClient.updateCredentials] silently ignores a partial triple, so
  /// completeness is checked before calling it rather than after.
  bool _isComplete(ServerConfig config) =>
      config.clientId.trim().isNotEmpty &&
      config.clientSecret.trim().isNotEmpty &&
      config.code.trim().isNotEmpty;
}
