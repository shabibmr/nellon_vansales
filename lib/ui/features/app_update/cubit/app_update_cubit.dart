import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/app_update_service.dart';
import '../../../../domain/models/app_update_info.dart';
import 'app_update_state.dart';

/// Cubit managing update lifecycle: checking Firestore, downloading APK, and triggering installer.
class AppUpdateCubit extends Cubit<AppUpdateState> {
  final AppUpdateService updateService;
  StreamSubscription<OtaEvent>? _otaSubscription;
  StreamSubscription<AppUpdateInfo?>? _watchSubscription;
  bool _watching = false;

  AppUpdateCubit({required this.updateService}) : super(AppUpdateInitial());

  bool get isInFlight => state.isInFlight;

  /// Current update channel ('production' or 'beta')
  String get activeChannel => updateService.activeChannel;

  /// Switches the active channel ('production' or 'beta') and refreshes version check
  Future<void> switchChannel(String channel) async {
    if (state.isInFlight) return;
    await updateService.setChannel(channel);
    _watchSubscription?.cancel();
    _watching = false;
    await startWatching();
  }

  /// One-shot check, then listen for live Firestore changes.
  Future<void> startWatching() async {
    if (_watching) return;
    _watching = true;
    await checkForUpdate();
    _watchSubscription?.cancel();
    _watchSubscription = updateService.watchAppVersion().listen(
      _applyRemoteInfo,
      onError: (Object e) {
        if (state.isInFlight) return;
        emit(AppUpdateError(message: 'Could not watch for updates: $e'));
      },
    );
  }

  /// Checks Firestore for newer releases against the local package version.
  ///
  /// No-op while a download or install is in flight so resume cannot reset progress.
  Future<void> checkForUpdate() async {
    if (state.isInFlight) return;
    emit(AppUpdateChecking());
    try {
      final info = await updateService.checkForUpdate();
      if (state.isInFlight) return;
      _applyRemoteInfo(info);
    } catch (e) {
      if (state.isInFlight) return;
      emit(AppUpdateError(message: 'Could not check for updates: $e'));
    }
  }

  /// Downloads the APK from the VPS URL and launches Android Package Installer.
  ///
  /// A second call for the same URL while already downloading/installing is ignored.
  void startDownloadAndInstall(AppUpdateInfo info) {
    final current = state;
    if (current.isInFlight && current.updateInfo?.apkUrl == info.apkUrl) {
      return;
    }

    _otaSubscription?.cancel();

    emit(AppUpdateDownloading(
      updateInfo: info,
      progress: 0.0,
      statusText: 'Connecting to server...',
    ));

    try {
      _otaSubscription = updateService
          .downloadAndInstallApk(info.apkUrl, sha256: info.sha256)
          .listen(
        (OtaEvent event) {
          switch (event.status) {
            case OtaStatus.downloading:
              final currentProgress =
                  (double.tryParse(event.value ?? '0') ?? 0) / 100.0;
              emit(AppUpdateDownloading(
                updateInfo: info,
                progress: currentProgress.clamp(0.0, 1.0),
                statusText: 'Downloading update: ${event.value}%',
              ));
              break;

            case OtaStatus.installing:
              emit(AppUpdateInstalling(updateInfo: info));
              break;

            case OtaStatus.alreadyRunningError:
              emit(AppUpdateDownloading(
                updateInfo: info,
                progress: 0.5,
                statusText: 'Download is already running...',
              ));
              break;

            case OtaStatus.permissionNotGrantedError:
              emit(AppUpdateError(
                message:
                    'Permission to install unknown apps was denied. Please allow it in Android Settings.',
                updateInfo: info,
              ));
              break;

            case OtaStatus.checksumError:
              emit(AppUpdateError(
                message:
                    'Downloaded file did not match the expected hash. The APK was not installed.',
                updateInfo: info,
              ));
              break;

            case OtaStatus.internalError:
            case OtaStatus.downloadError:
              emit(AppUpdateError(
                message:
                    'Download failed (${event.status.name}). Please check VPS connectivity and file URL.',
                updateInfo: info,
              ));
              break;
          }
        },
        onError: (Object e) {
          emit(AppUpdateError(
            message: 'Error during update download: $e',
            updateInfo: info,
          ));
        },
      );
    } catch (e) {
      emit(AppUpdateError(
        message: 'Could not start OTA download: $e',
        updateInfo: info,
      ));
    }
  }

  void _applyRemoteInfo(AppUpdateInfo? info) {
    if (state.isInFlight) return;
    if (info == null) {
      emit(AppUpdateInitial());
      return;
    }
    if (info.isUpdateAvailable) {
      emit(AppUpdateAvailable(updateInfo: info));
    } else {
      emit(AppUpdateUpToDate(updateInfo: info));
    }
  }

  @override
  Future<void> close() {
    _otaSubscription?.cancel();
    _watchSubscription?.cancel();
    return super.close();
  }
}
