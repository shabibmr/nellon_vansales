import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/app_update_info.dart';
import 'app_logger.dart';
import 'hive_database_service.dart';

/// Status events emitted during OTA APK download and installation.
enum OtaStatus {
  downloading,
  installing,
  alreadyRunningError,
  permissionNotGrantedError,
  internalError,
  downloadError,
  checksumError,
}

/// Event model representing download progress or status update.
class OtaEvent {
  final OtaStatus status;
  final String? value;

  const OtaEvent(this.status, [this.value]);
}

/// Coordinates remote Firestore version checks and native OTA APK updates.
class AppUpdateService {
  final FirebaseFirestore? firestoreInstance;
  final HiveDatabaseService? dbService;

  AppUpdateService({
    this.firestoreInstance,
    this.dbService,
  });

  FirebaseFirestore get firestore =>
      firestoreInstance ?? FirebaseFirestore.instance;

  /// Active channel ('production' or 'beta').
  String get activeChannel => dbService?.updateChannel ?? 'production';

  /// Switches active channel and persists in local database.
  Future<void> setChannel(String channel) async {
    await dbService?.setUpdateChannel(channel);
  }

  DocumentReference<Map<String, dynamic>> get _docRef {
    final docName = activeChannel == 'beta' ? 'app_version_beta' : 'app_version';
    return firestore.collection('server_config').doc(docName);
  }

  /// Fetches `server_config/app_version` once and compares with the installed build.
  ///
  /// A missing document is treated as up to date. Clients never write this doc.
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final local = await _localVersion();
      final doc = await _docRef.get();

      if (!doc.exists || doc.data() == null) {
        AppLogger.info(
          'AppUpdateService',
          'No server_config/app_version doc; treating local v${local.version}+${local.build} as current.',
        );
        return AppUpdateInfo.upToDate(
          currentBuildNumber: local.build,
          currentVersionName: local.version,
        );
      }

      return _parse(doc.data()!, local);
    } catch (e) {
      AppLogger.error('AppUpdateService', 'Failed to check app update: $e');
      return null;
    }
  }

  /// Live snapshots of `server_config/app_version`. Missing doc → up to date.
  Stream<AppUpdateInfo?> watchAppVersion() async* {
    late final ({int build, String version}) local;
    try {
      local = await _localVersion();
    } catch (e) {
      AppLogger.error('AppUpdateService', 'Failed to read local package version: $e');
      yield null;
      return;
    }

    yield* _docRef.snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return AppUpdateInfo.upToDate(
          currentBuildNumber: local.build,
          currentVersionName: local.version,
        );
      }
      return _parse(doc.data()!, local);
    }).handleError((Object e) {
      AppLogger.error('AppUpdateService', 'Failed to watch app update: $e');
    });
  }

  /// Downloads APK from [apkUrl] and triggers the Android package installer.
  ///
  /// [sha256] is verified before invoking Android package installer.
  Stream<OtaEvent> downloadAndInstallApk(String apkUrl, {required String sha256}) {
    final controller = StreamController<OtaEvent>();

    () async {
      try {
        if (!Platform.isAndroid) {
          controller.add(const OtaEvent(
            OtaStatus.internalError,
            'OTA updates are only supported on Android devices.',
          ));
          await controller.close();
          return;
        }

        if (sha256.trim().isEmpty) {
          controller.add(const OtaEvent(
            OtaStatus.checksumError,
            'APK checksum is required.',
          ));
          await controller.close();
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final targetFile = File('${tempDir.path}/van_sales_update.apk');
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }

        final dio = Dio();
        controller.add(const OtaEvent(OtaStatus.downloading, '0'));

        await dio.download(
          apkUrl,
          targetFile.path,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final percent = ((received / total) * 100).clamp(0, 100).toInt();
              controller.add(OtaEvent(OtaStatus.downloading, '$percent'));
            }
          },
        );

        // Check SHA256 checksum
        final bytes = await targetFile.readAsBytes();
        final computedHash = crypto.sha256.convert(bytes).toString();
        if (computedHash.toLowerCase() != sha256.trim().toLowerCase()) {
          controller.add(OtaEvent(
            OtaStatus.checksumError,
            'Checksum mismatch: expected $sha256 but got $computedHash',
          ));
          await controller.close();
          return;
        }

        controller.add(const OtaEvent(OtaStatus.installing));

        // Invoke native Android Package Installer
        const platform = MethodChannel('com.algoray.nellon/app_installer');
        await platform.invokeMethod('installApk', {'filePath': targetFile.path});

        await controller.close();
      } catch (e) {
        AppLogger.error('AppUpdateService', 'Download/Install failed: $e');
        controller.add(OtaEvent(OtaStatus.downloadError, e.toString()));
        await controller.close();
      }
    }();

    return controller.stream;
  }

  Future<({int build, String version})> _localVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return (
      build: int.tryParse(packageInfo.buildNumber) ?? 0,
      version: packageInfo.version,
    );
  }

  AppUpdateInfo _parse(
    Map<String, dynamic> data,
    ({int build, String version}) local,
  ) {
    final info = AppUpdateInfo.fromFirestore(
      data: data,
      currentBuildNumber: local.build,
      currentVersionName: local.version,
    );
    AppLogger.info(
      'AppUpdateService',
      'Version check: local=v${local.version}+${local.build}, '
      'remote=v${info.latestVersionName}+${info.latestBuildNumber}, '
      'updateAvailable=${info.isUpdateAvailable}',
    );
    return info;
  }
}
