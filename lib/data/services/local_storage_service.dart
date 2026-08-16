import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/server_config.dart';

/// Secure local storage for the device license UUID and last-good Zoho credentials.
class LocalStorageService {
  final FlutterSecureStorage _secureStorage;
  static const String _uuidKey = 'license_uuid';
  static const String _zohoClientIdKey = 'zoho_client_id';
  static const String _zohoClientSecretKey = 'zoho_client_secret';
  static const String _zohoRefreshTokenKey = 'zoho_refresh_token';
  static const String _zohoOrganizationIdKey = 'zoho_organization_id';

  LocalStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Reads the unique secure license UUID. Returns null if not yet generated.
  Future<String?> getLicenseUuid() async {
    try {
      return await _secureStorage.read(key: _uuidKey);
    } catch (_) {
      return null;
    }
  }

  /// Writes the unique license UUID securely to the device keychain/keystore.
  Future<void> saveLicenseUuid(String uuid) async {
    try {
      await _secureStorage.write(key: _uuidKey, value: uuid);
    } catch (e) {
      throw Exception('Failed to write license UUID securely: $e');
    }
  }

  /// Last complete Zoho OAuth triple written after a successful remote inject.
  ///
  /// Returns null if any of client id / secret / refresh token is missing.
  Future<ServerConfig?> readZohoCredentials() async {
    try {
      final clientId = await _secureStorage.read(key: _zohoClientIdKey);
      final clientSecret = await _secureStorage.read(key: _zohoClientSecretKey);
      final refreshToken = await _secureStorage.read(key: _zohoRefreshTokenKey);
      final organizationId = await _secureStorage.read(
        key: _zohoOrganizationIdKey,
      );
      if (clientId == null ||
          clientId.isEmpty ||
          clientSecret == null ||
          clientSecret.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return null;
      }
      return ServerConfig(
        clientId: clientId,
        clientSecret: clientSecret,
        code: refreshToken,
        organizationId: organizationId ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists a complete Zoho config so fail-open / offline boots can refresh.
  Future<void> saveZohoCredentials(ServerConfig config) async {
    try {
      await _secureStorage.write(key: _zohoClientIdKey, value: config.clientId);
      await _secureStorage.write(
        key: _zohoClientSecretKey,
        value: config.clientSecret,
      );
      await _secureStorage.write(key: _zohoRefreshTokenKey, value: config.code);
      await _secureStorage.write(
        key: _zohoOrganizationIdKey,
        value: config.organizationId,
      );
    } catch (e) {
      throw Exception('Failed to write Zoho credentials securely: $e');
    }
  }
}
