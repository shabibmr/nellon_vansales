import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:van_sales/data/repositories/print_settings_repository_impl.dart';
import 'package:van_sales/data/services/local_storage_service.dart';
import 'package:van_sales/domain/models/print_settings.dart';
import 'package:van_sales/domain/repositories/print_settings_repository.dart';

class _FakeLocalStorage extends LocalStorageService {
  String? phone;
  int saveCount = 0;

  @override
  Future<String?> readSupervisorPhone() async => phone;

  @override
  Future<void> saveSupervisorPhone(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    saveCount++;
    this.phone = trimmed;
  }
}

class _StubFirestore extends Fake implements FirebaseFirestore {
  _StubFirestore(this._reader);

  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(
    String collection,
    String doc,
  ) _reader;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _StubCollectionReference(
      collectionPath,
      _reader,
    );
  }
}

class _StubCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _StubCollectionReference(this._path, this._reader);

  final String _path;
  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(
    String collection,
    String doc,
  ) _reader;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    return _StubDocumentReference(_path, path ?? '', _reader);
  }
}

class _StubDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _StubDocumentReference(this._collection, this._doc, this._reader);

  final String _collection;
  final String _doc;
  final Future<DocumentSnapshot<Map<String, dynamic>>> Function(
    String collection,
    String doc,
  ) _reader;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) {
    return _reader(_collection, _doc);
  }
}

class _StubDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _StubDocumentSnapshot({required this.exists, Map<String, dynamic>? data})
      : _data = data;

  @override
  final bool exists;

  final Map<String, dynamic>? _data;

  @override
  Map<String, dynamic>? data() => _data;
}

class MemoryPrintSettingsRepository implements PrintSettingsRepository {
  MemoryPrintSettingsRepository([
    this._phone = PrintSettings.fallbackSupervisorPhone,
  ]);

  String _phone;

  @override
  String get supervisorPhone => _phone;

  @override
  Future<void> hydrate() async {}

  @override
  Future<PrintSettings> refresh() async =>
      PrintSettings(supervisorPhone: _phone);

  void setPhone(String value) => _phone = value;
}

void main() {
  group('MemoryPrintSettingsRepository', () {
    test('exposes configured phone for resolution-rule consumers', () {
      final repo = MemoryPrintSettingsRepository('+971 50 111 2222');
      expect(repo.supervisorPhone, '+971 50 111 2222');
    });
  });

  group('PrintSettingsRepositoryImpl', () {
    late _FakeLocalStorage storage;
    late PrintSettingsRepositoryImpl repository;

    setUp(() {
      storage = _FakeLocalStorage();
      repository = PrintSettingsRepositoryImpl(localStorage: storage);
    });

    test('supervisorPhone uses fallback before hydrate', () {
      expect(
        repository.supervisorPhone,
        PrintSettings.fallbackSupervisorPhone,
      );
    });

    test('hydrate loads cached phone from local storage', () async {
      storage.phone = '+971 50 999 8888';

      await repository.hydrate();

      expect(repository.supervisorPhone, '+971 50 999 8888');
    });

    test('non-empty remote overwrites cache and persists to storage', () async {
      storage.phone = '+971 50 111 1111';
      await repository.hydrate();

      final firestore = _StubFirestore((collection, doc) async {
        expect(collection, 'server_config');
        expect(doc, 'print');
        return _StubDocumentSnapshot(
          exists: true,
          data: {'supervisor_phone': '+971 50 222 2222'},
        );
      });

      repository = PrintSettingsRepositoryImpl(
        localStorage: storage,
        firestore: firestore,
      );
      await repository.hydrate();

      final settings = await repository.refresh();

      expect(settings.supervisorPhone, '+971 50 222 2222');
      expect(repository.supervisorPhone, '+971 50 222 2222');
      expect(storage.phone, '+971 50 222 2222');
      expect(storage.saveCount, 1);
    });

    test('empty remote leaves previous cache and does not save', () async {
      storage.phone = '+971 50 333 3333';
      await repository.hydrate();

      final firestore = _StubFirestore((collection, doc) async {
        return _StubDocumentSnapshot(
          exists: true,
          data: {'supervisor_phone': '   '},
        );
      });

      repository = PrintSettingsRepositoryImpl(
        localStorage: storage,
        firestore: firestore,
      );
      await repository.hydrate();

      final settings = await repository.refresh();

      expect(settings.supervisorPhone, '+971 50 333 3333');
      expect(repository.supervisorPhone, '+971 50 333 3333');
      expect(storage.phone, '+971 50 333 3333');
      expect(storage.saveCount, 0);
    });

    test('thrown fetch leaves previous cache', () async {
      storage.phone = '+971 50 444 4444';
      await repository.hydrate();

      final firestore = _StubFirestore((collection, doc) async {
        throw Exception('network down');
      });

      repository = PrintSettingsRepositoryImpl(
        localStorage: storage,
        firestore: firestore,
      );
      await repository.hydrate();

      final settings = await repository.refresh();

      expect(settings.supervisorPhone, '+971 50 444 4444');
      expect(repository.supervisorPhone, '+971 50 444 4444');
      expect(storage.saveCount, 0);
    });

    test('missing document leaves fallback when cache is empty', () async {
      final firestore = _StubFirestore((collection, doc) async {
        return _StubDocumentSnapshot(exists: false);
      });

      repository = PrintSettingsRepositoryImpl(
        localStorage: storage,
        firestore: firestore,
      );

      final settings = await repository.refresh();

      expect(settings.supervisorPhone, PrintSettings.fallbackSupervisorPhone);
      expect(repository.supervisorPhone, PrintSettings.fallbackSupervisorPhone);
      expect(storage.saveCount, 0);
    });
  });

  group('LocalStorageService supervisor phone Hive round-trip', () {
    late Directory tempDir;
    late Box<dynamic> box;
    late LocalStorageService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_print_test_');
      Hive.init(tempDir.path);
      box = await Hive.openBox<dynamic>(LocalStorageService.boxName);
      service = LocalStorageService(box: box);
    });

    tearDown(() async {
      await box.close();
      await Hive.deleteBoxFromDisk(LocalStorageService.boxName);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saveSupervisorPhone persists and readSupervisorPhone reads it', () async {
      const phone = '+971 50 555 6666';
      await service.saveSupervisorPhone(phone);

      final result = await service.readSupervisorPhone();
      expect(result, phone);
    });

    test('saveSupervisorPhone ignores empty values', () async {
      await service.saveSupervisorPhone('  ');
      expect(await service.readSupervisorPhone(), isNull);
    });
  });
}
