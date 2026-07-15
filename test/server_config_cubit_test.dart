import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/server_config.dart';
import 'package:van_sales/ui/features/licensing/cubit/server_config_cubit.dart';
import 'package:van_sales/ui/features/licensing/cubit/server_config_state.dart';

class FakeHiveDatabaseService extends HiveDatabaseService {
  bool? transactionMockModeEnabledValue;

  @override
  bool? get transactionMockModeEnabled => transactionMockModeEnabledValue;

  @override
  Future<void> setTransactionMockModeEnabled(bool enabled) async {
    transactionMockModeEnabledValue = enabled;
  }
}

void main() {
  group('ServerConfigCubit', () {
    late FakeHiveDatabaseService db;
    late ZohoApiClient apiClient;
    late ServerConfigCubit cubit;

    const config = ServerConfig(
      clientId: 'client',
      clientSecret: 'secret',
      code: 'refresh',
      mockTransactions: true,
      mockSalesOrderTransactions: false,
      mockStockTransfers: true,
    );

    setUp(() {
      db = FakeHiveDatabaseService();
      apiClient = ZohoApiClient(dbService: db);
      cubit = ServerConfigCubit(apiClient: apiClient, dbService: db);
    });

    tearDown(() => cubit.close());

    test('bootstraps mock mode from hive on construction', () {
      db.transactionMockModeEnabledValue = false;

      final freshCubit = ServerConfigCubit(
        apiClient: apiClient,
        dbService: db,
      );

      expect(freshCubit.state, isA<ServerConfigInitial>());
      expect(freshCubit.state.isMockModeEnabled, isFalse);
      expect(apiClient.isMockModeEnabled, isFalse);
      freshCubit.close();
    });

    test('setConfig null keeps switch state in initial', () {
      cubit.setConfig(null);

      expect(cubit.state, isA<ServerConfigInitial>());
      expect(cubit.state.isMockModeEnabled, isTrue);
    });

    test(
      'setConfig with empty credentials emits error and keeps existing creds',
      () {
        const emptyConfig = ServerConfig(
          clientId: '',
          clientSecret: '',
          code: '',
        );

        cubit.setConfig(emptyConfig);

        expect(cubit.state, isA<ServerConfigError>());
        // The client must not have been switched into placeholder/empty mode.
        expect(apiClient.usesPlaceholderCredentials, isFalse);
      },
    );

    test('setConfig enables mock when any remote flag is true', () {
      cubit.setConfig(config);

      expect(cubit.state, isA<ServerConfigLoaded>());
      final loaded = cubit.state as ServerConfigLoaded;
      expect(loaded.isMockModeEnabled, isTrue);
      expect(apiClient.isMockModeEnabled, isTrue);
    });

    test('setConfig uses persisted override over remote config', () {
      db.transactionMockModeEnabledValue = false;

      cubit.setConfig(config);

      final loaded = cubit.state as ServerConfigLoaded;
      expect(loaded.isMockModeEnabled, isFalse);
      expect(apiClient.isMockModeEnabled, isFalse);
    });

    test('setMockModeEnabled toggles all flags and persists', () async {
      cubit.setConfig(config);

      await cubit.setMockModeEnabled(false);

      final loaded = cubit.state as ServerConfigLoaded;
      expect(loaded.isMockModeEnabled, isFalse);
      expect(apiClient.isMockModeEnabled, isFalse);
      expect(db.transactionMockModeEnabledValue, isFalse);

      await cubit.setMockModeEnabled(true);

      final reloaded = cubit.state as ServerConfigLoaded;
      expect(reloaded.isMockModeEnabled, isTrue);
      expect(apiClient.isMockModeEnabled, isTrue);
      expect(db.transactionMockModeEnabledValue, isTrue);
    });
  });
}