import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/local_storage_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/server_config.dart';
import 'package:van_sales/ui/features/licensing/cubit/server_config_cubit.dart';
import 'package:van_sales/ui/features/licensing/cubit/server_config_state.dart';

class FakeHiveDatabaseService extends HiveDatabaseService {
  String? storedAccessToken = 'stale-access-token';
  int? storedExpiry = 9999999999999;

  @override
  String? get oauthAccessToken => storedAccessToken;

  @override
  Future<void> setOauthAccessToken(String? token) async {
    storedAccessToken = token;
  }

  @override
  int? get oauthTokenExpiry => storedExpiry;

  @override
  Future<void> setOauthTokenExpiry(int? expiryMillis) async {
    storedExpiry = expiryMillis;
  }
}

class FakeLocalStorageService extends LocalStorageService {
  ServerConfig? cached;
  Duration readDelay = Duration.zero;

  @override
  Future<ServerConfig?> readZohoCredentials() async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return cached;
  }

  @override
  Future<void> saveZohoCredentials(ServerConfig config) async {
    cached = config;
  }
}

void main() {
  group('ServerConfigCubit', () {
    late FakeHiveDatabaseService db;
    late FakeLocalStorageService storage;
    late ZohoApiClient apiClient;
    late ServerConfigCubit cubit;

    const config = ServerConfig(
      clientId: 'client',
      clientSecret: 'secret',
      code: 'refresh',
      organizationId: 'org-1',
    );

    const otherConfig = ServerConfig(
      clientId: 'client-b',
      clientSecret: 'secret-b',
      code: 'refresh-b',
      organizationId: 'org-2',
    );

    ServerConfigCubit buildCubit() {
      return ServerConfigCubit(apiClient: apiClient, localStorage: storage);
    }

    setUp(() {
      db = FakeHiveDatabaseService();
      storage = FakeLocalStorageService();
      apiClient = ZohoApiClient(dbService: db);
      cubit = buildCubit();
    });

    tearDown(() => cubit.close());

    test('starts in initial state without cache', () async {
      await cubit.hydrateDone;
      expect(cubit.state, isA<ServerConfigInitial>());
      expect(apiClient.hasCredentials, isFalse);
    });

    test('hydrates credentials from secure cache on construct', () async {
      await cubit.close();
      storage.cached = config;
      apiClient = ZohoApiClient(dbService: db);
      cubit = buildCubit();

      await cubit.hydrateDone;

      expect(cubit.state, isA<ServerConfigLoaded>());
      final loaded = cubit.state as ServerConfigLoaded;
      expect(loaded.clientId, 'client');
      expect(loaded.clientSecret, 'secret');
      expect(loaded.code, 'refresh');
      expect(apiClient.hasCredentials, isTrue);
    });

    test('setConfig injects credentials, persists cache, and emits loaded',
        () async {
      cubit.setConfig(config);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isA<ServerConfigLoaded>());
      final loaded = cubit.state as ServerConfigLoaded;
      expect(loaded.clientId, 'client');
      expect(loaded.clientSecret, 'secret');
      expect(loaded.code, 'refresh');
      expect(apiClient.hasCredentials, isTrue);
      expect(storage.cached, config);
    });

    test('setConfig null returns to initial without wiping injected creds',
        () async {
      cubit.setConfig(config);
      await Future<void>.delayed(Duration.zero);
      cubit.setConfig(null);

      expect(cubit.state, isA<ServerConfigInitial>());
      expect(apiClient.hasCredentials, isTrue);
      expect(storage.cached, config);
    });

    test(
      'setConfig with empty credentials emits error and keeps existing creds',
      () async {
        cubit.setConfig(config);
        await Future<void>.delayed(Duration.zero);

        const emptyConfig = ServerConfig(
          clientId: '',
          clientSecret: '',
          code: '',
        );
        cubit.setConfig(emptyConfig);

        expect(cubit.state, isA<ServerConfigError>());
        expect(
          (cubit.state as ServerConfigError).message,
          contains('incomplete'),
        );
        expect(apiClient.hasCredentials, isTrue);
        expect(storage.cached, config);
      },
    );

    test('changing the OAuth triple clears the cached access token', () async {
      cubit.setConfig(config);
      await Future<void>.delayed(Duration.zero);
      expect(db.storedAccessToken, isNull);
      expect(db.storedExpiry, isNull);

      db.storedAccessToken = 'fresh-token';
      db.storedExpiry = 123;
      cubit.setConfig(config);
      await Future<void>.delayed(Duration.zero);
      expect(db.storedAccessToken, 'fresh-token');
      expect(db.storedExpiry, 123);

      cubit.setConfig(otherConfig);
      await Future<void>.delayed(Duration.zero);
      expect(db.storedAccessToken, isNull);
      expect(db.storedExpiry, isNull);
    });

    test('hydrate does not overwrite an already-loaded remote config', () async {
      await cubit.close();
      storage.cached = config;
      storage.readDelay = const Duration(milliseconds: 30);
      apiClient = ZohoApiClient(dbService: db);
      cubit = buildCubit();

      cubit.setConfig(otherConfig);
      await cubit.hydrateDone;

      expect(cubit.state, isA<ServerConfigLoaded>());
      final loaded = cubit.state as ServerConfigLoaded;
      expect(loaded.clientId, otherConfig.clientId);
      expect(loaded.code, otherConfig.code);
    });

    test('reset returns to initial', () {
      cubit.setConfig(config);
      cubit.reset();
      expect(cubit.state, isA<ServerConfigInitial>());
    });
  });
}
