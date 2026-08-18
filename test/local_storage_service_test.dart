import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:van_sales/data/services/local_storage_service.dart';
import 'package:van_sales/domain/models/server_config.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late LocalStorageService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
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

  group('LocalStorageService', () {
    test('getLicenseUuid returns null when no UUID is saved', () async {
      final uuid = await service.getLicenseUuid();
      expect(uuid, isNull);
    });

    test('saveLicenseUuid persists UUID and getLicenseUuid reads it', () async {
      const testUuid = '123e4567-e89b-12d3-a456-426614174000';
      await service.saveLicenseUuid(testUuid);

      final result = await service.getLicenseUuid();
      expect(result, equals(testUuid));
    });

    test('readZohoCredentials returns null when box is empty or incomplete', () async {
      final config = await service.readZohoCredentials();
      expect(config, isNull);

      // Incomplete credentials
      await box.put('zoho_client_id', 'client_123');
      final incomplete = await service.readZohoCredentials();
      expect(incomplete, isNull);
    });

    test('saveZohoCredentials persists complete triple and readZohoCredentials recovers it', () async {
      const config = ServerConfig(
        clientId: 'test-client-id',
        clientSecret: 'test-client-secret',
        code: 'test-refresh-token',
        organizationId: 'test-org-123',
      );

      await service.saveZohoCredentials(config);

      final result = await service.readZohoCredentials();
      expect(result, isNotNull);
      expect(result!.clientId, equals('test-client-id'));
      expect(result.clientSecret, equals('test-client-secret'));
      expect(result.code, equals('test-refresh-token'));
      expect(result.organizationId, equals('test-org-123'));
    });
  });
}
