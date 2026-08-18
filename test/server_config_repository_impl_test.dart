import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/repositories/server_config_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/license_service.dart';
import 'package:van_sales/data/services/local_storage_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/server_config.dart';

class _FakeHiveDatabaseService extends HiveDatabaseService {
  String? token;
  int? expiry;

  @override
  String? get oauthAccessToken => token;

  @override
  Future<void> setOauthAccessToken(String? t) async {
    token = t;
  }

  @override
  int? get oauthTokenExpiry => expiry;

  @override
  Future<void> setOauthTokenExpiry(int? e) async {
    expiry = e;
  }
}

class _FakeLocalStorageService extends LocalStorageService {
  ServerConfig? cached;
  int saveCount = 0;

  @override
  Future<ServerConfig?> readZohoCredentials() async => cached;

  @override
  Future<void> saveZohoCredentials(ServerConfig config) async {
    saveCount++;
    cached = config;
  }
}

class _FakeLicenseService extends LicenseService {
  ServerConfig? configToReturn;
  bool shouldThrow = false;
  int fetchCount = 0;

  @override
  Future<ServerConfig> fetchServerConfig() async {
    fetchCount++;
    if (shouldThrow) {
      throw Exception('Firestore permission denied');
    }
    if (configToReturn == null) {
      return const ServerConfig(
        clientId: '',
        clientSecret: '',
        code: '',
        organizationId: '',
      );
    }
    return configToReturn!;
  }
}

void main() {
  group('ServerConfigRepositoryImpl', () {
    late _FakeHiveDatabaseService db;
    late _FakeLocalStorageService storage;
    late _FakeLicenseService licenseService;
    late ZohoApiClient apiClient;
    late ServerConfigRepositoryImpl repository;

    const validConfig = ServerConfig(
      clientId: 'cid_123',
      clientSecret: 'secret_456',
      code: 'refresh_789',
      organizationId: 'org_999',
    );

    const rotatedConfig = ServerConfig(
      clientId: 'cid_rotated',
      clientSecret: 'secret_rotated',
      code: 'refresh_rotated',
      organizationId: 'org_999',
    );

    setUp(() {
      db = _FakeHiveDatabaseService();
      storage = _FakeLocalStorageService();
      licenseService = _FakeLicenseService();
      apiClient = ZohoApiClient(dbService: db);
      repository = ServerConfigRepositoryImpl(
        apiClient: apiClient,
        localStorage: storage,
        licenseService: licenseService,
      );
    });

    test('still fetches Firestore when ZohoApiClient already has credentials',
        () async {
      apiClient.updateCredentials(
        clientId: 'cid',
        clientSecret: 'secret',
        refreshToken: 'refresh',
      );
      licenseService.shouldThrow = true;

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(licenseService.fetchCount, 1);
      expect(storage.saveCount, 0);
    });

    test('still fetches Firestore when secure cache is already complete',
        () async {
      storage.cached = validConfig;
      licenseService.shouldThrow = true;

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(apiClient.hasCredentials, isTrue);
      expect(licenseService.fetchCount, 1);
      expect(storage.saveCount, 0);
      expect(storage.cached, validConfig);
    });

    test(
        'fetches from remote Firestore on fresh install and caches to local storage',
        () async {
      storage.cached = null;
      licenseService.configToReturn = validConfig;

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(apiClient.hasCredentials, isTrue);
      expect(licenseService.fetchCount, 1);
      expect(storage.saveCount, 1);
      expect(storage.cached, validConfig);
    });

    test('complete remote with a different client id overwrites cache',
        () async {
      storage.cached = validConfig;
      apiClient.updateCredentials(
        clientId: validConfig.clientId,
        clientSecret: validConfig.clientSecret,
        refreshToken: validConfig.code,
        organizationId: validConfig.organizationId,
      );
      licenseService.configToReturn = rotatedConfig;

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(licenseService.fetchCount, 1);
      expect(storage.saveCount, 1);
      expect(storage.cached, rotatedConfig);
    });

    test('incomplete remote keeps existing in-memory credentials and does not save',
        () async {
      apiClient.updateCredentials(
        clientId: validConfig.clientId,
        clientSecret: validConfig.clientSecret,
        refreshToken: validConfig.code,
        organizationId: validConfig.organizationId,
      );
      licenseService.configToReturn = const ServerConfig(
        clientId: 'cid_only',
        clientSecret: '',
        code: '',
      );

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(apiClient.hasCredentials, isTrue);
      expect(storage.saveCount, 0);
    });

    test('incomplete remote keeps secure cache and does not save', () async {
      storage.cached = validConfig;
      licenseService.configToReturn = const ServerConfig(
        clientId: 'cid_only',
        clientSecret: '',
        code: '',
      );

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(apiClient.hasCredentials, isTrue);
      expect(storage.saveCount, 0);
      expect(storage.cached, validConfig);
    });

    test('returns false when remote Firestore config is incomplete', () async {
      storage.cached = null;
      licenseService.configToReturn = const ServerConfig(
        clientId: 'cid_only',
        clientSecret: '',
        code: '',
      );

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isFalse);
      expect(apiClient.hasCredentials, isFalse);
      expect(storage.saveCount, 0);
    });

    test('fail-open: remote throw with valid cache still returns true',
        () async {
      storage.cached = validConfig;
      licenseService.shouldThrow = true;

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isTrue);
      expect(apiClient.hasCredentials, isTrue);
      expect(licenseService.fetchCount, 1);
      expect(storage.saveCount, 0);
    });

    test('returns false gracefully when remote Firestore fetch throws',
        () async {
      storage.cached = null;
      licenseService.shouldThrow = true;

      final result = await repository.ensureCredentialsLoaded();
      expect(result, isFalse);
      expect(apiClient.hasCredentials, isFalse);
      expect(storage.saveCount, 0);
    });
  });
}
