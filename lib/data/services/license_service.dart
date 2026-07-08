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
  ///
  /// If the document does not exist, it is created with default live settings.
  /// If any specific key is missing from the document, it is automatically
  /// populated and updated in Firestore.
  Future<ServerConfig> fetchServerConfig() async {
    try {
      final docRef = firestore.collection('server_config').doc('zoho');
      final doc = await docRef.get();

      final defaultData = {
        'client_id': '',
        'client_secret': '',
        'code': '',
        'mock_transactions': false,
        'mock_sales_order_transactions': false,
        'mock_stock_transfers': false,
      };

      if (!doc.exists || doc.data() == null) {
        await docRef.set(defaultData);
        return ServerConfig.fromMap(defaultData);
      }

      final data = Map<String, dynamic>.from(doc.data()!);
      final missingUpdates = <String, dynamic>{};
      
      for (final entry in defaultData.entries) {
        if (!data.containsKey(entry.key)) {
          missingUpdates[entry.key] = entry.value;
        }
      }

      if (missingUpdates.isNotEmpty) {
        await docRef.update(missingUpdates);
        data.addAll(missingUpdates);
      }

      return ServerConfig.fromMap(data);
    } catch (e) {
      throw Exception(
        'Failed to read and auto-populate Zoho server configuration from Firestore: $e',
      );
    }
  }
}
