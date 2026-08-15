import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/app_update_service.dart';
import 'package:van_sales/domain/models/app_update_info.dart';
import 'package:van_sales/ui/features/app_update/cubit/app_update_cubit.dart';
import 'package:van_sales/ui/features/app_update/cubit/app_update_state.dart';

const _sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

AppUpdateInfo _info({
  int latest = 2,
  int current = 1,
  String url = 'https://vps.example.com/app.apk',
  String sha256 = _sha,
  bool force = false,
  bool? available,
  String notes = '',
  String latestName = '1.0.1',
  String currentName = '1.0.0',
}) {
  return AppUpdateInfo(
    latestBuildNumber: latest,
    latestVersionName: latestName,
    apkUrl: url,
    sha256: sha256,
    forceUpdate: force,
    releaseNotes: notes,
    currentBuildNumber: current,
    currentVersionName: currentName,
    isUpdateAvailable: available ?? (latest > current && url.isNotEmpty && sha256.isNotEmpty),
  );
}

class MockAppUpdateService extends AppUpdateService {
  AppUpdateInfo? mockUpdateInfo;
  bool shouldThrow = false;
  final StreamController<OtaEvent> _otaController =
      StreamController<OtaEvent>.broadcast();
  final StreamController<AppUpdateInfo?> watchController =
      StreamController<AppUpdateInfo?>.broadcast();
  int downloadStarts = 0;
  String? lastSha256;

  String _channel = 'production';

  MockAppUpdateService({this.mockUpdateInfo});

  @override
  String get activeChannel => _channel;

  @override
  Future<void> setChannel(String channel) async {
    _channel = channel;
  }

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (shouldThrow) {
      throw Exception('Network timeout connecting to Firestore');
    }
    return mockUpdateInfo;
  }

  @override
  Stream<AppUpdateInfo?> watchAppVersion() => watchController.stream;

  @override
  Stream<OtaEvent> downloadAndInstallApk(String apkUrl, {required String sha256}) {
    downloadStarts += 1;
    lastSha256 = sha256;
    return _otaController.stream;
  }

  void emitOtaEvent(OtaEvent event) {
    _otaController.add(event);
  }

  void dispose() {
    _otaController.close();
    watchController.close();
  }
}

void main() {
  group('AppUpdateInfo Model Tests', () {
    test('marks update available when build is greater and URL and sha256 are present', () {
      final info = AppUpdateInfo.fromFirestore(
        data: const {
          'latest_build_number': 10,
          'latest_version_name': '2.0.0',
          'apk_url': 'https://vps.example.com/app.apk',
          'sha256': _sha,
          'force_update': true,
          'release_notes': 'New invoice features',
        },
        currentBuildNumber: 5,
        currentVersionName: '1.0.0',
      );

      expect(info.isUpdateAvailable, isTrue);
      expect(info.latestBuildNumber, 10);
      expect(info.sha256, _sha);
      expect(info.forceUpdate, isTrue);
    });

    test('marks update not available when latest build number <= current build number', () {
      final info = AppUpdateInfo.fromFirestore(
        data: const {
          'latest_build_number': 5,
          'latest_version_name': '1.0.0',
          'apk_url': 'https://vps.example.com/app.apk',
          'sha256': _sha,
          'force_update': false,
          'release_notes': '',
        },
        currentBuildNumber: 5,
        currentVersionName: '1.0.0',
      );

      expect(info.isUpdateAvailable, isFalse);
    });

    test('marks update not available if apk_url is empty', () {
      final info = AppUpdateInfo.fromFirestore(
        data: const {
          'latest_build_number': 10,
          'latest_version_name': '2.0.0',
          'apk_url': '',
          'sha256': _sha,
          'force_update': false,
          'release_notes': '',
        },
        currentBuildNumber: 5,
        currentVersionName: '1.0.0',
      );

      expect(info.isUpdateAvailable, isFalse);
    });

    test('marks update not available if sha256 is empty', () {
      final info = AppUpdateInfo.fromFirestore(
        data: const {
          'latest_build_number': 10,
          'latest_version_name': '2.0.0',
          'apk_url': 'https://vps.example.com/app.apk',
          'sha256': '',
          'force_update': false,
          'release_notes': '',
        },
        currentBuildNumber: 5,
        currentVersionName: '1.0.0',
      );

      expect(info.isUpdateAvailable, isFalse);
    });

    test('marks update not available if sha256 is missing', () {
      final info = AppUpdateInfo.fromFirestore(
        data: const {
          'latest_build_number': 10,
          'latest_version_name': '2.0.0',
          'apk_url': 'https://vps.example.com/app.apk',
          'force_update': false,
        },
        currentBuildNumber: 5,
        currentVersionName: '1.0.0',
      );

      expect(info.isUpdateAvailable, isFalse);
      expect(info.sha256, isEmpty);
    });
  });

  group('AppUpdateCubit Tests', () {
    late MockAppUpdateService service;
    late AppUpdateCubit cubit;

    setUp(() {
      service = MockAppUpdateService();
      cubit = AppUpdateCubit(updateService: service);
    });

    tearDown(() {
      cubit.close();
      service.dispose();
    });

    test('initial state is AppUpdateInitial', () {
      expect(cubit.state, isA<AppUpdateInitial>());
    });

    test('emits AppUpdateChecking then AppUpdateAvailable when an update is available', () async {
      service.mockUpdateInfo = _info(latest: 3, latestName: '1.0.2', force: true, notes: 'Fixed sync');

      expectLater(
        cubit.stream,
        emitsInOrder([
          isA<AppUpdateChecking>(),
          isA<AppUpdateAvailable>().having(
            (s) => s.updateInfo.latestVersionName,
            'latestVersionName',
            '1.0.2',
          ),
        ]),
      );

      await cubit.checkForUpdate();
    });

    test('emits AppUpdateChecking then AppUpdateUpToDate when already on latest version', () async {
      service.mockUpdateInfo = _info(latest: 1, current: 1, available: false);

      expectLater(
        cubit.stream,
        emitsInOrder([
          isA<AppUpdateChecking>(),
          isA<AppUpdateUpToDate>(),
        ]),
      );

      await cubit.checkForUpdate();
    });

    test('emits AppUpdateError when check throws an exception', () async {
      service.shouldThrow = true;

      expectLater(
        cubit.stream,
        emitsInOrder([
          isA<AppUpdateChecking>(),
          isA<AppUpdateError>(),
        ]),
      );

      await cubit.checkForUpdate();
    });

    test('tracks download progress events from OTA stream', () async {
      final updateInfo = _info();

      cubit.startDownloadAndInstall(updateInfo);
      expect(cubit.state, isA<AppUpdateDownloading>());
      expect(service.lastSha256, _sha);

      service.emitOtaEvent(const OtaEvent(OtaStatus.downloading, '45'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = cubit.state;
      expect(state, isA<AppUpdateDownloading>());
      expect((state as AppUpdateDownloading).progress, 0.45);
      expect(state.statusText, 'Downloading update: 45%');
    });

    test('emits a dedicated error when the APK checksum does not match', () async {
      cubit.startDownloadAndInstall(_info());
      service.emitOtaEvent(const OtaEvent(OtaStatus.checksumError, 'mismatch'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = cubit.state;
      expect(state, isA<AppUpdateError>());
      expect(
        (state as AppUpdateError).message,
        contains('expected hash'),
      );
    });

    test('checkForUpdate is a no-op while downloading', () async {
      cubit.startDownloadAndInstall(_info());
      expect(cubit.state, isA<AppUpdateDownloading>());

      service.mockUpdateInfo = _info(latest: 9);
      await cubit.checkForUpdate();

      expect(cubit.state, isA<AppUpdateDownloading>());
    });

    test('second startDownloadAndInstall for the same URL does not reset progress', () async {
      final info = _info();
      cubit.startDownloadAndInstall(info);
      service.emitOtaEvent(const OtaEvent(OtaStatus.downloading, '45'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.startDownloadAndInstall(info);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.downloadStarts, 1);
      final state = cubit.state;
      expect(state, isA<AppUpdateDownloading>());
      expect((state as AppUpdateDownloading).progress, 0.45);
    });

    test('watch snapshot emits Available then is ignored during download', () async {
      service.mockUpdateInfo = _info(latest: 1, current: 1, available: false);

      await cubit.startWatching();
      expect(cubit.state, isA<AppUpdateUpToDate>());

      service.watchController.add(_info(latest: 4, latestName: '1.2.0'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state, isA<AppUpdateAvailable>());
      expect((cubit.state as AppUpdateAvailable).updateInfo.latestVersionName, '1.2.0');

      cubit.startDownloadAndInstall(_info(latest: 4));
      service.watchController.add(_info(latest: 5, latestName: '1.3.0'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state, isA<AppUpdateDownloading>());
    });

    test('switchChannel changes channel and restarts watching', () async {
      service.mockUpdateInfo = _info(latest: 1, current: 1, available: false);
      await cubit.startWatching();
      expect(cubit.activeChannel, 'production');

      service.mockUpdateInfo = _info(latest: 5, latestName: '2.0.0-beta', available: true);
      await cubit.switchChannel('beta');

      expect(cubit.activeChannel, 'beta');
      expect(service.activeChannel, 'beta');
      expect(cubit.state, isA<AppUpdateAvailable>());
      expect((cubit.state as AppUpdateAvailable).updateInfo.latestVersionName, '2.0.0-beta');
    });
  });
}
