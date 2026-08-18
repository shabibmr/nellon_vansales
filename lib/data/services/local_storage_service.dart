import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/models/server_config.dart';
import 'debug_file_logger.dart';

/// Local storage for the device license UUID and last-good Zoho credentials backed by Hive.
class LocalStorageService {
  static const String boxName = 'app_config_box';
  static const String _uuidKey = 'license_uuid';
  static const String _zohoClientIdKey = 'zoho_client_id';
  static const String _zohoClientSecretKey = 'zoho_client_secret';
  static const String _zohoRefreshTokenKey = 'zoho_refresh_token';
  static const String _zohoOrganizationIdKey = 'zoho_organization_id';

  final Box<dynamic>? box;

  LocalStorageService({this.box});

  Future<Box<dynamic>> _getBox() async {
    final explicitBox = box;
    if (explicitBox != null && explicitBox.isOpen) return explicitBox;
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<dynamic>(boxName);
    }
    return await Hive.openBox<dynamic>(boxName);
  }

  /// Reads the unique license UUID. Returns null if not yet generated.
  Future<String?> getLicenseUuid() async {
    try {
      final box = await _getBox();
      return box.get(_uuidKey) as String?;
    } catch (e) {
      DebugFileLogger.log('[LocalStorage] ❌ getLicenseUuid error: $e');
      return null;
    }
  }

  /// Writes the unique license UUID locally.
  Future<void> saveLicenseUuid(String uuid) async {
    try {
      final box = await _getBox();
      await box.put(_uuidKey, uuid);
    } catch (e) {
      throw Exception('Failed to write license UUID: $e');
    }
  }

  /// Last complete Zoho OAuth triple written after a successful remote inject.
  ///
  /// Returns null if any of client id / secret / refresh token is missing.
  Future<ServerConfig?> readZohoCredentials() async {
    DebugFileLogger.log('[LocalStorage] 🔍 readZohoCredentials: reading from Hive...');
    try {
      final box = await _getBox();
      final clientId = box.get(_zohoClientIdKey) as String?;
      final clientSecret = box.get(_zohoClientSecretKey) as String?;
      final refreshToken = box.get(_zohoRefreshTokenKey) as String?;
      final organizationId = box.get(_zohoOrganizationIdKey) as String?;
      DebugFileLogger.log(
        '[LocalStorage] 📥 readZohoCredentials: raw values — '
        'clientId="$clientId", clientSecret="$clientSecret", '
        'refreshToken="$refreshToken", organizationId="$organizationId"',
      );
      if (clientId == null ||
          clientId.isEmpty ||
          clientSecret == null ||
          clientSecret.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        DebugFileLogger.log(
          '[LocalStorage] ⚠️ readZohoCredentials: INCOMPLETE — '
          'clientId.isEmptyOrNull=${clientId == null || clientId.isEmpty}, '
          'clientSecret.isEmptyOrNull=${clientSecret == null || clientSecret.isEmpty}, '
          'refreshToken.isEmptyOrNull=${refreshToken == null || refreshToken.isEmpty} — returning null.',
        );
        return null;
      }
      DebugFileLogger.log('[LocalStorage] ✅ readZohoCredentials: complete config found.');
      return ServerConfig(
        clientId: clientId,
        clientSecret: clientSecret,
        code: refreshToken,
        organizationId: organizationId ?? '',
      );
    } catch (e) {
      DebugFileLogger.log('[LocalStorage] ❌ readZohoCredentials: EXCEPTION (swallowed, returning null): $e');
      return null;
    }
  }

  /// Persists a complete Zoho config so fail-open / offline boots can refresh.
  Future<void> saveZohoCredentials(ServerConfig config) async {
    DebugFileLogger.log(
      '[LocalStorage] 💾 saveZohoCredentials: writing — '
      'clientId="${config.clientId}", clientSecret="${config.clientSecret}", '
      'code="${config.code}", organizationId="${config.organizationId}"',
    );
    try {
      final box = await _getBox();
      await Future.wait([
        box.put(_zohoClientIdKey, config.clientId),
        box.put(_zohoClientSecretKey, config.clientSecret),
        box.put(_zohoRefreshTokenKey, config.code),
        box.put(_zohoOrganizationIdKey, config.organizationId),
      ]);
      DebugFileLogger.log('[LocalStorage] ✅ saveZohoCredentials: write succeeded.');
    } catch (e) {
      DebugFileLogger.log('[LocalStorage] ❌ saveZohoCredentials: write FAILED: $e');
      throw Exception('Failed to write Zoho credentials: $e');
    }
  }
}
