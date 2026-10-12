# Review package Task 2
BASE d592b75c30a417d2877174f70f46c85f961f5c6b
HEAD 5f242e5fac66d3650e0613084efd508f78675664
## Commits
5f242e5 Load supervisor phone from server_config/print with Hive cache.

## Stat
 .../print_settings_repository_impl.dart            |  64 +++++
 lib/data/services/local_storage_service.dart       |  24 ++
 .../repositories/print_settings_repository.dart    |  12 +
 test/local_storage_service_test.dart               |  13 +
 test/print_settings_repository_impl_test.dart      | 269 +++++++++++++++++++++
 5 files changed, 382 insertions(+)

## Diff
diff --git a/lib/data/repositories/print_settings_repository_impl.dart b/lib/data/repositories/print_settings_repository_impl.dart
new file mode 100644
index 0000000..977d8e6
--- /dev/null
+++ b/lib/data/repositories/print_settings_repository_impl.dart
@@ -0,0 +1,64 @@
+import 'package:cloud_firestore/cloud_firestore.dart';
+
+import '../../domain/models/print_settings.dart';
+import '../../domain/repositories/print_settings_repository.dart';
+import '../services/app_logger.dart';
+import '../services/error_classification.dart';
+import '../services/local_storage_service.dart';
+
+class PrintSettingsRepositoryImpl implements PrintSettingsRepository {
+  PrintSettingsRepositoryImpl({
+    required LocalStorageService localStorage,
+    FirebaseFirestore? firestore,
+  })  : _localStorage = localStorage,
+        _firestore = firestore;
+
+  final LocalStorageService _localStorage;
+  final FirebaseFirestore? _firestore;
+  String _cached = PrintSettings.fallbackSupervisorPhone;
+
+  FirebaseFirestore get firestore =>
+      _firestore ?? FirebaseFirestore.instance;
+
+  @override
+  String get supervisorPhone =>
+      _cached.trim().isEmpty ? PrintSettings.fallbackSupervisorPhone : _cached;
+
+  @override
+  Future<void> hydrate() async {
+    final stored = await _localStorage.readSupervisorPhone();
+    if (stored != null && stored.isNotEmpty) {
+      _cached = stored;
+    }
+  }
+
+  @override
+  Future<PrintSettings> refresh() async {
+    try {
+      final doc = await firestore
+          .collection('server_config')
+          .doc('print')
+          .get()
+          .timeout(const Duration(seconds: 8));
+      if (doc.exists && doc.data() != null) {
+        final remote = PrintSettings.fromMap(doc.data()!);
+        if (remote.supervisorPhone.isNotEmpty) {
+          _cached = remote.supervisorPhone;
+          await _localStorage.saveSupervisorPhone(_cached);
+        }
+      }
+    } catch (e) {
+      AppLogger.warning(
+        'PrintSettings',
+        'Failed to fetch server_config/print: $e',
+      );
+      if (isFirestorePermissionDenied(e)) {
+        AppLogger.error(
+          'PrintSettings',
+          'Firestore permission-denied reading server_config/print.',
+        );
+      }
+    }
+    return PrintSettings(supervisorPhone: supervisorPhone);
+  }
+}
diff --git a/lib/data/services/local_storage_service.dart b/lib/data/services/local_storage_service.dart
index 9f6a44a..0f23493 100644
--- a/lib/data/services/local_storage_service.dart
+++ b/lib/data/services/local_storage_service.dart
@@ -3,20 +3,21 @@ import '../../domain/models/server_config.dart';
 import 'debug_file_logger.dart';
 
 /// Local storage for the device license UUID and last-good Zoho credentials backed by Hive.
 class LocalStorageService {
   static const String boxName = 'app_config_box';
   static const String _uuidKey = 'license_uuid';
   static const String _zohoClientIdKey = 'zoho_client_id';
   static const String _zohoClientSecretKey = 'zoho_client_secret';
   static const String _zohoRefreshTokenKey = 'zoho_refresh_token';
   static const String _zohoOrganizationIdKey = 'zoho_organization_id';
+  static const String _supervisorPhoneKey = 'supervisor_phone';
 
   final Box<dynamic>? box;
 
   LocalStorageService({this.box});
 
   Future<Box<dynamic>> _getBox() async {
     final explicitBox = box;
     if (explicitBox != null && explicitBox.isOpen) return explicitBox;
     if (Hive.isBoxOpen(boxName)) {
       return Hive.box<dynamic>(boxName);
@@ -102,11 +103,34 @@ class LocalStorageService {
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
+
+  Future<String?> readSupervisorPhone() async {
+    try {
+      final box = await _getBox();
+      final value = (box.get(_supervisorPhoneKey) as String?)?.trim();
+      if (value == null || value.isEmpty) return null;
+      return value;
+    } catch (e) {
+      DebugFileLogger.log('[LocalStorage] ❌ readSupervisorPhone error: $e');
+      return null;
+    }
+  }
+
+  Future<void> saveSupervisorPhone(String phone) async {
+    final trimmed = phone.trim();
+    if (trimmed.isEmpty) return;
+    try {
+      final box = await _getBox();
+      await box.put(_supervisorPhoneKey, trimmed);
+    } catch (e) {
+      DebugFileLogger.log('[LocalStorage] ❌ saveSupervisorPhone FAILED: $e');
+    }
+  }
 }
diff --git a/lib/domain/repositories/print_settings_repository.dart b/lib/domain/repositories/print_settings_repository.dart
new file mode 100644
index 0000000..1d1f127
--- /dev/null
+++ b/lib/domain/repositories/print_settings_repository.dart
@@ -0,0 +1,12 @@
+import '../models/print_settings.dart';
+
+abstract class PrintSettingsRepository {
+  /// Cached (or fallback) phone for PDF/thermal. Never empty.
+  String get supervisorPhone;
+
+  /// Loads last-good phone from Hive into memory. No-op when cache is empty.
+  Future<void> hydrate();
+
+  /// Fetches `server_config/print`, updates cache when the field is non-empty.
+  Future<PrintSettings> refresh();
+}
diff --git a/test/local_storage_service_test.dart b/test/local_storage_service_test.dart
index 764a1dd..cea493b 100644
--- a/test/local_storage_service_test.dart
+++ b/test/local_storage_service_test.dart
@@ -58,12 +58,25 @@ void main() {
 
       await service.saveZohoCredentials(config);
 
       final result = await service.readZohoCredentials();
       expect(result, isNotNull);
       expect(result!.clientId, equals('test-client-id'));
       expect(result.clientSecret, equals('test-client-secret'));
       expect(result.code, equals('test-refresh-token'));
       expect(result.organizationId, equals('test-org-123'));
     });
+
+    test('saveSupervisorPhone persists phone and readSupervisorPhone reads it', () async {
+      const phone = '+971 50 777 8888';
+      await service.saveSupervisorPhone(phone);
+
+      final result = await service.readSupervisorPhone();
+      expect(result, equals(phone));
+    });
+
+    test('saveSupervisorPhone ignores empty values', () async {
+      await service.saveSupervisorPhone('  ');
+      expect(await service.readSupervisorPhone(), isNull);
+    });
   });
 }
diff --git a/test/print_settings_repository_impl_test.dart b/test/print_settings_repository_impl_test.dart
new file mode 100644
index 0000000..ec6b003
--- /dev/null
+++ b/test/print_settings_repository_impl_test.dart
@@ -0,0 +1,269 @@
+import 'dart:io';
+
+import 'package:cloud_firestore/cloud_firestore.dart';
+import 'package:flutter_test/flutter_test.dart';
+import 'package:hive_flutter/hive_flutter.dart';
+import 'package:van_sales/data/repositories/print_settings_repository_impl.dart';
+import 'package:van_sales/data/services/local_storage_service.dart';
+import 'package:van_sales/domain/models/print_settings.dart';
+import 'package:van_sales/domain/repositories/print_settings_repository.dart';
+
+class _FakeLocalStorage extends LocalStorageService {
+  String? phone;
+  int saveCount = 0;
+
+  @override
+  Future<String?> readSupervisorPhone() async => phone;
+
+  @override
+  Future<void> saveSupervisorPhone(String phone) async {
+    final trimmed = phone.trim();
+    if (trimmed.isEmpty) return;
+    saveCount++;
+    this.phone = trimmed;
+  }
+}
+
+class _StubFirestore extends Fake implements FirebaseFirestore {
+  _StubFirestore(this._reader);
+
+  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(
+    String collection,
+    String doc,
+  ) _reader;
+
+  @override
+  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
+    return _StubCollectionReference(
+      collectionPath,
+      _reader,
+    );
+  }
+}
+
+class _StubCollectionReference extends Fake
+    implements CollectionReference<Map<String, dynamic>> {
+  _StubCollectionReference(this._path, this._reader);
+
+  final String _path;
+  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(
+    String collection,
+    String doc,
+  ) _reader;
+
+  @override
+  DocumentReference<Map<String, dynamic>> doc([String? path]) {
+    return _StubDocumentReference(_path, path ?? '', _reader);
+  }
+}
+
+class _StubDocumentReference extends Fake
+    implements DocumentReference<Map<String, dynamic>> {
+  _StubDocumentReference(this._collection, this._doc, this._reader);
+
+  final String _collection;
+  final String _doc;
+  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(
+    String collection,
+    String doc,
+  ) _reader;
+
+  @override
+  Future<DocumentSnapshot<Map<String, dynamic>>> get([
+    GetOptions? options,
+  ]) {
+    return _reader(_collection, _doc);
+  }
+}
+
+class _StubDocumentSnapshot extends Fake
+    implements DocumentSnapshot<Map<String, dynamic>> {
+  _StubDocumentSnapshot({required this.exists, Map<String, dynamic>? data})
+      : _data = data;
+
+  @override
+  final bool exists;
+
+  final Map<String, dynamic>? _data;
+
+  @override
+  Map<String, dynamic>? data() => _data;
+}
+
+class MemoryPrintSettingsRepository implements PrintSettingsRepository {
+  MemoryPrintSettingsRepository([
+    this._phone = PrintSettings.fallbackSupervisorPhone,
+  ]);
+
+  String _phone;
+
+  @override
+  String get supervisorPhone => _phone;
+
+  @override
+  Future<void> hydrate() async {}
+
+  @override
+  Future<PrintSettings> refresh() async =>
+      PrintSettings(supervisorPhone: _phone);
+
+  void setPhone(String value) => _phone = value;
+}
+
+void main() {
+  group('MemoryPrintSettingsRepository', () {
+    test('exposes configured phone for resolution-rule consumers', () {
+      final repo = MemoryPrintSettingsRepository('+971 50 111 2222');
+      expect(repo.supervisorPhone, '+971 50 111 2222');
+    });
+  });
+
+  group('PrintSettingsRepositoryImpl', () {
+    late _FakeLocalStorage storage;
+    late PrintSettingsRepositoryImpl repository;
+
+    setUp(() {
+      storage = _FakeLocalStorage();
+      repository = PrintSettingsRepositoryImpl(localStorage: storage);
+    });
+
+    test('supervisorPhone uses fallback before hydrate', () {
+      expect(
+        repository.supervisorPhone,
+        PrintSettings.fallbackSupervisorPhone,
+      );
+    });
+
+    test('hydrate loads cached phone from local storage', () async {
+      storage.phone = '+971 50 999 8888';
+
+      await repository.hydrate();
+
+      expect(repository.supervisorPhone, '+971 50 999 8888');
+    });
+
+    test('non-empty remote overwrites cache and persists to storage', () async {
+      storage.phone = '+971 50 111 1111';
+      await repository.hydrate();
+
+      final firestore = _StubFirestore((collection, doc) async {
+        expect(collection, 'server_config');
+        expect(doc, 'print');
+        return _StubDocumentSnapshot(
+          exists: true,
+          data: {'supervisor_phone': '+971 50 222 2222'},
+        );
+      });
+
+      repository = PrintSettingsRepositoryImpl(
+        localStorage: storage,
+        firestore: firestore,
+      );
+      await repository.hydrate();
+
+      final settings = await repository.refresh();
+
+      expect(settings.supervisorPhone, '+971 50 222 2222');
+      expect(repository.supervisorPhone, '+971 50 222 2222');
+      expect(storage.phone, '+971 50 222 2222');
+      expect(storage.saveCount, 1);
+    });
+
+    test('empty remote leaves previous cache and does not save', () async {
+      storage.phone = '+971 50 333 3333';
+      await repository.hydrate();
+
+      final firestore = _StubFirestore((collection, doc) async {
+        return _StubDocumentSnapshot(
+          exists: true,
+          data: {'supervisor_phone': '   '},
+        );
+      });
+
+      repository = PrintSettingsRepositoryImpl(
+        localStorage: storage,
+        firestore: firestore,
+      );
+      await repository.hydrate();
+
+      final settings = await repository.refresh();
+
+      expect(settings.supervisorPhone, '+971 50 333 3333');
+      expect(repository.supervisorPhone, '+971 50 333 3333');
+      expect(storage.phone, '+971 50 333 3333');
+      expect(storage.saveCount, 0);
+    });
+
+    test('thrown fetch leaves previous cache', () async {
+      storage.phone = '+971 50 444 4444';
+      await repository.hydrate();
+
+      final firestore = _StubFirestore((collection, doc) async {
+        throw Exception('network down');
+      });
+
+      repository = PrintSettingsRepositoryImpl(
+        localStorage: storage,
+        firestore: firestore,
+      );
+      await repository.hydrate();
+
+      final settings = await repository.refresh();
+
+      expect(settings.supervisorPhone, '+971 50 444 4444');
+      expect(repository.supervisorPhone, '+971 50 444 4444');
+      expect(storage.saveCount, 0);
+    });
+
+    test('missing document leaves fallback when cache is empty', () async {
+      final firestore = _StubFirestore((collection, doc) async {
+        return _StubDocumentSnapshot(exists: false);
+      });
+
+      repository = PrintSettingsRepositoryImpl(
+        localStorage: storage,
+        firestore: firestore,
+      );
+
+      final settings = await repository.refresh();
+
+      expect(settings.supervisorPhone, PrintSettings.fallbackSupervisorPhone);
+      expect(repository.supervisorPhone, PrintSettings.fallbackSupervisorPhone);
+      expect(storage.saveCount, 0);
+    });
+  });
+
+  group('LocalStorageService supervisor phone Hive round-trip', () {
+    late Directory tempDir;
+    late Box<dynamic> box;
+    late LocalStorageService service;
+
+    setUp(() async {
+      tempDir = await Directory.systemTemp.createTemp('hive_print_test_');
+      Hive.init(tempDir.path);
+      box = await Hive.openBox<dynamic>(LocalStorageService.boxName);
+      service = LocalStorageService(box: box);
+    });
+
+    tearDown(() async {
+      await box.close();
+      await Hive.deleteBoxFromDisk(LocalStorageService.boxName);
+      if (tempDir.existsSync()) {
+        tempDir.deleteSync(recursive: true);
+      }
+    });
+
+    test('saveSupervisorPhone persists and readSupervisorPhone reads it', () async {
+      const phone = '+971 50 555 6666';
+      await service.saveSupervisorPhone(phone);
+
+      final result = await service.readSupervisorPhone();
+      expect(result, phone);
+    });
+
+    test('saveSupervisorPhone ignores empty values', () async {
+      await service.saveSupervisorPhone('  ');
+      expect(await service.readSupervisorPhone(), isNull);
+    });
+  });
+}
