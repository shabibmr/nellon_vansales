import 'package:equatable/equatable.dart';
import '../../../../domain/models/app_update_info.dart';

/// Base state for application update lifecycle.
abstract class AppUpdateState extends Equatable {
  const AppUpdateState();

  AppUpdateInfo? get updateInfo => null;

  bool get isInFlight => false;

  bool get isForceBlocking {
    final info = updateInfo;
    if (info == null || !info.forceUpdate) return false;
    return this is AppUpdateAvailable ||
        this is AppUpdateDownloading ||
        this is AppUpdateInstalling ||
        this is AppUpdateError;
  }

  @override
  List<Object?> get props => [];
}

/// Initial state before any update check is performed.
class AppUpdateInitial extends AppUpdateState {}

/// State while checking Firestore for newer releases.
class AppUpdateChecking extends AppUpdateState {}

/// State when the current installed app is already on the latest version.
class AppUpdateUpToDate extends AppUpdateState {
  @override
  final AppUpdateInfo updateInfo;

  const AppUpdateUpToDate({required this.updateInfo});

  @override
  List<Object?> get props => [updateInfo];
}

/// State when a newer APK release is found on Firestore.
class AppUpdateAvailable extends AppUpdateState {
  @override
  final AppUpdateInfo updateInfo;

  const AppUpdateAvailable({required this.updateInfo});

  @override
  List<Object?> get props => [updateInfo];
}

/// State while downloading the APK file from the VPS.
class AppUpdateDownloading extends AppUpdateState {
  @override
  final AppUpdateInfo updateInfo;
  final double progress; // 0.0 to 1.0
  final String statusText;

  const AppUpdateDownloading({
    required this.updateInfo,
    required this.progress,
    required this.statusText,
  });

  @override
  bool get isInFlight => true;

  @override
  List<Object?> get props => [updateInfo, progress, statusText];
}

/// State when APK download completes and native Android package installer is launched.
class AppUpdateInstalling extends AppUpdateState {
  @override
  final AppUpdateInfo updateInfo;

  const AppUpdateInstalling({required this.updateInfo});

  @override
  bool get isInFlight => true;

  @override
  List<Object?> get props => [updateInfo];
}

/// State when an error occurs during update check or APK download.
class AppUpdateError extends AppUpdateState {
  final String message;
  @override
  final AppUpdateInfo? updateInfo;

  const AppUpdateError({
    required this.message,
    this.updateInfo,
  });

  @override
  List<Object?> get props => [message, updateInfo];
}
