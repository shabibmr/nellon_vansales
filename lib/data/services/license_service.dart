import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/models/license_document.dart';
import '../../domain/models/server_config.dart';

/// Pure Dart service to coordinate Firestore read/write tasks for app licensing and control.
class LicenseService {
  final FirebaseFirestore? _firestore;

  LicenseService({this._firestore});

  /// Lazily resolves active Firestore instance
  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  /// Fetches an app license by its unique stored UUID string. Returns null if not found.
  Future<LicenseDocument?> fetchLicense(String uuid) async {
    try {
      final doc = await firestore.collection('app_licenses').doc(uuid).get();
      if (doc.exists && doc.data() != null) {
        return LicenseDocument.fromMap(doc.data()!);
      }
    } catch (e) {
      throw Exception('Failed to fetch app license document: $e');
    }
    return null;
  }

  /// Registers and writes a new license document into Firestore collection `app_licenses`.
  Future<void> createLicense(LicenseDocument doc) async {
    try {
      await firestore.collection('app_licenses').doc(doc.id).set(doc.toMap());
    } catch (e) {
      throw Exception('Failed to create app license document: $e');
    }
  }

  /// Dynamically updates the `last_login_at` timestamp field to the server current time.
  Future<void> updateLastLogin(String uuid) async {
    try {
      await firestore.collection('app_licenses').doc(uuid).update({
        'last_login_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update last login timestamp: $e');
    }
  }

  /// Reads and parses remote Zoho API integration configurations from `server_config/zoho`.
  Future<ServerConfig> fetchServerConfig() async {
    try {
      final doc = await firestore.collection('server_config').doc('zoho').get();
      if (doc.exists && doc.data() != null) {
        return ServerConfig.fromMap(doc.data()!);
      }
    } catch (e) {
      throw Exception(
        'Failed to read Zoho server configuration from Firestore: $e',
      );
    }
    throw Exception(
      'Server configuration document "zoho" not found under "server_config" collection.',
    );
  }
}
