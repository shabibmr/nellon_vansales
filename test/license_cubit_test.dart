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
  String appVersion = '1.0.0+1';

  @override
  Future<DeviceDetails> getDeviceDetails() async {
    return DeviceDetails(
      id: 'test_device_id',
      model: 'test_model',
      os: 'Android',
      osVersion: '13',
      appVersion: appVersion,
    );
  }
}

class FakeLicenseService extends LicenseService {
  LicenseDocument? document;
  ServerConfig? serverConfig;
  bool shouldThrowFetch = false;
  bool shouldThrowCreate = false;
  bool shouldThrowSync = false;
  Object fetchError = Exception('Network connection timed out');

  int syncCallCount = 0;
  String? syncUuid;
  Map<String, dynamic>? syncFields;
  bool? syncAppVersionChanged;

  @override
  Future<LicenseDocument?> fetchLicense(String uuid) async {
    if (shouldThrowFetch) {
      throw fetchError;
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
  Future<void> syncLoginMetadata(
    String uuid,
    Map<String, dynamic> fields, {
    bool appVersionChanged = false,
  }) async {
    syncCallCount++;
    syncUuid = uuid;
    syncFields = fields;
    syncAppVersionChanged = appVersionChanged;
    if (shouldThrowSync) {
      throw Exception('sync failed');
    }
  }

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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
    'checkLicense refreshes login metadata for a valid license',
    () async {
      localService.uuid = 'my-uuid-v4';
      deviceService.appVersion = '2.0.0+40';
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

      await cubit.checkLicense(testUser);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(licenseService.syncCallCount, 1);
      expect(licenseService.syncUuid, 'my-uuid-v4');
      expect(licenseService.syncFields!['app_version'], '2.0.0+40');
      expect(licenseService.syncFields!['previous_app_version'], '1.0.0+1');
      expect(licenseService.syncAppVersionChanged, isTrue);
    },
  );

  test(
    'checkLicense does not flag an app-version change when the build is unchanged',
    () async {
      localService.uuid = 'my-uuid-v4';
      deviceService.appVersion = '1.0.0+1';
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

      await cubit.checkLicense(testUser);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(licenseService.syncCallCount, 1);
      expect(licenseService.syncAppVersionChanged, isFalse);
      expect(licenseService.syncFields!.containsKey('previous_app_version'),
          isFalse);
    },
  );

  test(
    'checkLicense does not sync login metadata for a disabled license',
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

      await cubit.checkLicense(testUser);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(licenseService.syncCallCount, 0);
    },
  );

  test(
    'checkLicense stays valid when the login-metadata sync throws',
    () async {
      localService.uuid = 'my-uuid-v4';
      licenseService.shouldThrowSync = true;
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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
      expect(licenseService.document!.loginCount, 1);
      expect(licenseService.document!.previousAppVersion, '');
    },
  );

  test(
    'registerFirstLogin fails open and emits valid state when Firestore write fails',
    () async {
      licenseService.shouldThrowCreate = true;

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.registerFirstLogin(testUser);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(states, [
        LicenseChecking(),
        const LicenseValid(serverConfig: null),
      ]);
    },
  );

  test(
    'checkLicense emits error when Firestore returns permission-denied',
    () async {
      localService.uuid = 'my-uuid-v4';
      licenseService.shouldThrowFetch = true;
      licenseService.fetchError = Exception(
        '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
      );

      final states = <LicenseState>[];
      cubit.stream.listen(states.add);

      await cubit.checkLicense(testUser);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(states.first, LicenseChecking());
      expect(states.last, isA<LicenseError>());
    },
  );
}
