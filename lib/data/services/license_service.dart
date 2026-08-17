import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../domain/models/license_document.dart';
import '../../domain/models/server_config.dart';
import 'app_logger.dart';
import 'error_classification.dart';

/// Pure Dart service to coordinate Firestore read/write tasks for app licensing and control.
class LicenseService {
  final FirebaseFirestore? _firestore;

  LicenseService({this._firestore});

  /// Lazily resolves active Firestore instance
  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  /// Fetches an app license by its unique stored UUID string. Returns null if not found.
  Future<LicenseDocument?> fetchLicense(String uuid) async {
    try {
      final doc = await firestore
          .collection('app_licenses')
          .doc(uuid)
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null) {
        return LicenseDocument.fromMap(doc.data()!);
      }
    } catch (e) {
      AppLogger.warning('LicenseService', 'Failed to fetch license document: $e');
      if (isFirestorePermissionDenied(e)) {
        throw Exception(
          'Firestore permission-denied reading app_licenses: $e',
        );
      }
      throw Exception('Failed to fetch app license document: $e');
    }
    return null;
  }

  /// Registers and writes a new license document into Firestore collection `app_licenses`.
  Future<void> createLicense(LicenseDocument doc) async {
    try {
      await firestore
          .collection('app_licenses')
          .doc(doc.id)
          .set(doc.toMap())
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      AppLogger.warning('LicenseService', 'Failed to create license document: $e');
      if (isFirestorePermissionDenied(e)) {
        throw Exception(
          'Firestore permission-denied creating app_licenses: $e',
        );
      }
      throw Exception('Failed to create app license document: $e');
    }
  }

  /// Dynamically updates the `last_login_at` timestamp field to the server current time.
  Future<void> updateLastLogin(String uuid) async {
    try {
      await firestore
          .collection('app_licenses')
          .doc(uuid)
          .update({
            'last_login_at': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      AppLogger.warning('LicenseService', 'Failed to update last login timestamp: $e');
      throw Exception('Failed to update last login timestamp: $e');
    }
  }

  /// Reads remote Zoho API integration configurations from `server_config/zoho`.
  ///
  /// This is a pure read operation that never attempts to mutate Firestore from
  /// the client app, preventing permission-denied errors on devices with read-only rules.
  Future<ServerConfig> fetchServerConfig() async {
    try {
      debugPrint('[ServerConfig] 🔍 Fetching server_config/zoho from Firestore...');
      final doc = await firestore
          .collection('server_config')
          .doc('zoho')
          .get()
          .timeout(const Duration(seconds: 8));

      if (!doc.exists || doc.data() == null) {
        debugPrint(
          '[ServerConfig] ⚠️ server_config/zoho document DOES NOT EXIST or is null in Firestore!',
        );
        AppLogger.warning(
          'ServerConfig',
          'server_config/zoho doc does not exist or is empty in Firestore',
        );
        return const ServerConfig(
          clientId: '',
          clientSecret: '',
          code: '',
          organizationId: '',
        );
      }

      final data = doc.data()!;
      debugPrint('[ServerConfig] 📥 Received server_config/zoho from Firestore: $data');
      AppLogger.info(
        'ServerConfig',
        'Received server_config/zoho: keys=${data.keys.toList()}, '
        'clientId=${data['client_id']}, '
        'organizationId=${data['organization_id']}, '
        'hasCode=${data.containsKey('code')}, '
        'hasRefreshToken=${data.containsKey('refresh_token')}',
      );

      final config = ServerConfig.fromMap(data);
      debugPrint(
        '[ServerConfig] ✅ Parsed ServerConfig: '
        'clientId="${config.clientId}", '
        'clientSecretLength=${config.clientSecret.length}, '
        'codeLength=${config.code.length}, '
        'organizationId="${config.organizationId}", '
        'isValid=${config.isValid}',
      );

      return config;
    } catch (e) {
      debugPrint('[ServerConfig] ❌ Failed to fetch server_config/zoho: $e');
      AppLogger.error('ServerConfig', 'Failed to read Zoho server configuration: $e');
      if (isFirestorePermissionDenied(e)) {
        throw Exception(
          'Firestore permission-denied reading server_config/zoho: $e',
        );
      }
      throw Exception(
        'Failed to read Zoho server configuration from Firestore: $e',
      );
    }
  }
}
