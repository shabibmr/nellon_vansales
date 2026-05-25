import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure local storage service dedicated to managing license identifiers securely on device.
class LocalStorageService {
  final FlutterSecureStorage _secureStorage;
  static const String _uuidKey = 'license_uuid';

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
}
