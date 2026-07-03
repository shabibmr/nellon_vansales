import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/device_info_service.dart';
import 'package:van_sales/data/services/license_service.dart';
import 'package:van_sales/data/services/local_storage_service.dart';
import 'package:van_sales/domain/models/license_document.dart';
import 'package:van_sales/domain/models/server_config.dart';
import 'package:van_sales/domain/models/user.dart';
import 'package:van_sales/ui/features/licensing/cubit/license_cubit.dart';
import 'package:van_sales/ui/features/licensing/cubit/license_state.dart';

class FakeLocalStorageService extends LocalStorageService {
  String? uuid;

  @override
  Future<String?> getLicenseUuid() async => uuid;

  @override
  Future<void> saveLicenseUuid(String newUuid) async {
    uuid = newUuid;
  }
}

class FakeDeviceInfoService extends DeviceInfoService {
  @override
  Future<DeviceDetails> getDeviceDetails() async {
    return const DeviceDetails(
      id: 'test_device_id',
      model: 'test_model',
      os: 'Android',
      osVersion: '13',
      appVersion: '1.0.0+1',
    );
  }
}

class FakeLicenseService extends LicenseService {
  LicenseDocument? document;
  ServerConfig? serverConfig;
  bool shouldThrowFetch = false;
  bool shouldThrowCreate = false;

  @override
  Future<LicenseDocument?> fetchLicense(String uuid) async {
    if (shouldThrowFetch) {
      throw Exception('Network connection timed out');
    }
    return document;
  }

  @override
  Future<void> createLicense(LicenseDocument doc) async {
    if (shouldThrowCreate) {
      throw Exception('Firestore write permission denied');
    }
    document = doc;
  }

  @override
  Future<void> updateLastLogin(String uuid) async {}

  @override
  Future<ServerConfig> fetchServerConfig() async {
    if (serverConfig == null) {
      throw Exception('Server config not found');
    }
    return serverConfig!;
  }
}

void main() {
  late FakeLocalStorageService localService;
  late FakeDeviceInfoService deviceService;
  late FakeLicenseService licenseService;
  late LicenseCubit cubit;

  const testUser = User(
    id: 'user_123',
    name: 'John Agent',
    email: 'john@sales.com',
    role: 'agent',
  );

  setUp(() {
    localService = FakeLocalStorageService();
    deviceService = FakeDeviceInfoService();
    licenseService = FakeLicenseService();
    cubit = LicenseCubit(
      licenseService: licenseService,
      localStorageService: localService,
      deviceInfoService: deviceService,
    );
  });

  tearDown(() {
    cubit.close();
  });

  test(
    'checkLicense emits checking and then pending first login when no UUID exists locally',
    () async {
      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.checkLicense(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [LicenseChecking(), LicensePendingFirstLogin()]);
    },
  );

  test(
    'checkLicense emits checking and then valid when valid license exists remotely',
    () async {
      localService.uuid = 'my-uuid-v4';
      licenseService.document = LicenseDocument(
        id: 'my-uuid-v4',
        userId: 'user_123',
        userEmail: 'john@sales.com',
        userName: 'John Agent',
        deviceId: 'test_device_id',
        deviceModel: 'test_model',
        deviceOs: 'Android',
        deviceOsVersion: '13',
        appVersion: '1.0.0+1',
        firstLoginAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        enabled: true,
        expiryAt: DateTime.now().add(const Duration(days: 10)),
      );
      licenseService.serverConfig = const ServerConfig(
        clientId: 'zoho-id',
        clientSecret: 'zoho-secret',
        code: 'zoho-code',
      );

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.checkLicense(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseValid(
          serverConfig: ServerConfig(
            clientId: 'zoho-id',
            clientSecret: 'zoho-secret',
            code: 'zoho-code',
          ),
        ),
      ]);
    },
  );

  test(
    'checkLicense emits checking and then blocked when license is disabled',
    () async {
      localService.uuid = 'my-uuid-v4';
      licenseService.document = LicenseDocument(
        id: 'my-uuid-v4',
        userId: 'user_123',
        userEmail: 'john@sales.com',
        userName: 'John Agent',
        deviceId: 'test_device_id',
        deviceModel: 'test_model',
        deviceOs: 'Android',
        deviceOsVersion: '13',
        appVersion: '1.0.0+1',
        firstLoginAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        enabled: false,
        expiryAt: DateTime.now().add(const Duration(days: 10)),
      );

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.checkLicense(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseBlocked(
          reason:
              'Your application license has been disabled by the administrator.',
        ),
      ]);
    },
  );

  test(
    'checkLicense emits checking and then blocked when license is expired',
    () async {
      localService.uuid = 'my-uuid-v4';
      licenseService.document = LicenseDocument(
        id: 'my-uuid-v4',
        userId: 'user_123',
        userEmail: 'john@sales.com',
        userName: 'John Agent',
        deviceId: 'test_device_id',
        deviceModel: 'test_model',
        deviceOs: 'Android',
        deviceOsVersion: '13',
        appVersion: '1.0.0+1',
        firstLoginAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        enabled: true,
        expiryAt: DateTime.now().subtract(
          const Duration(days: 2),
        ), // expired 2 days ago
      );

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.checkLicense(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseBlocked(
          reason:
              'Your application license has expired. Please contact support.',
        ),
      ]);
    },
  );

  test(
    'checkLicense emits checking and then valid (fail-open) when Firestore fetch fails',
    () async {
      localService.uuid = 'my-uuid-v4';
      licenseService.shouldThrowFetch = true;

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.checkLicense(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseValid(serverConfig: null),
      ]);
    },
  );

  test(
    'registerFirstLogin registers trial license and emits valid state',
    () async {
      licenseService.serverConfig = const ServerConfig(
        clientId: 'zoho-id',
        clientSecret: 'zoho-secret',
        code: 'zoho-code',
      );

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.registerFirstLogin(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseValid(
          serverConfig: ServerConfig(
            clientId: 'zoho-id',
            clientSecret: 'zoho-secret',
            code: 'zoho-code',
          ),
        ),
      ]);

      // Verify UUID saved in storage
      expect(localService.uuid, isNotNull);
      expect(localService.uuid!.isNotEmpty, isTrue);

      // Verify document was created
      expect(licenseService.document, isNotNull);
      expect(licenseService.document!.userId, 'user_123');
      expect(licenseService.document!.userEmail, 'john@sales.com');
      expect(licenseService.document!.deviceId, 'test_device_id');
      expect(licenseService.document!.enabled, isTrue);
    },
  );

  test(
    'registerFirstLogin emits error state when Firestore write fails',
    () async {
      licenseService.shouldThrowCreate = true;

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.registerFirstLogin(testUser);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseError(
          'Failed to register application license: Firestore write permission denied',
        ),
      ]);
    },
  );
}
