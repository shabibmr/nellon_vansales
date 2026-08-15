import 'package:equatable/equatable.dart';

/// Represents application version status and metadata fetched from remote Firestore.
class AppUpdateInfo extends Equatable {
  final int latestBuildNumber;
  final String latestVersionName;
  final String apkUrl;
  final String sha256;
  final bool forceUpdate;
  final String releaseNotes;
  final int currentBuildNumber;
  final String currentVersionName;
  final bool isUpdateAvailable;

  const AppUpdateInfo({
    required this.latestBuildNumber,
    required this.latestVersionName,
    required this.apkUrl,
    required this.sha256,
    required this.forceUpdate,
    required this.releaseNotes,
    required this.currentBuildNumber,
    required this.currentVersionName,
    required this.isUpdateAvailable,
  });

  /// Local-only placeholder used when the remote document is missing.
  factory AppUpdateInfo.upToDate({
    required int currentBuildNumber,
    required String currentVersionName,
  }) {
    return AppUpdateInfo(
      latestBuildNumber: currentBuildNumber,
      latestVersionName: currentVersionName,
      apkUrl: '',
      sha256: '',
      forceUpdate: false,
      releaseNotes: '',
      currentBuildNumber: currentBuildNumber,
      currentVersionName: currentVersionName,
      isUpdateAvailable: false,
    );
  }

  /// Factory constructor parsing remote Firestore map and comparing with installed local version
  factory AppUpdateInfo.fromFirestore({
    required Map<String, dynamic> data,
    required int currentBuildNumber,
    required String currentVersionName,
  }) {
    final latestBuild = (data['latest_build_number'] as num?)?.toInt() ?? 0;
    final latestVersion = (data['latest_version_name'] as String?) ?? '1.0.0';
    final apkUrl = (data['apk_url'] as String?) ?? '';
    final sha256 = (data['sha256'] as String?) ?? '';
    final forceUpdate = (data['force_update'] as bool?) ?? false;
    final releaseNotes = (data['release_notes'] as String?) ?? '';

    final isUpdateAvailable =
        latestBuild > currentBuildNumber &&
        apkUrl.trim().isNotEmpty &&
        sha256.trim().isNotEmpty;

    return AppUpdateInfo(
      latestBuildNumber: latestBuild,
      latestVersionName: latestVersion,
      apkUrl: apkUrl.trim(),
      sha256: sha256.trim(),
      forceUpdate: forceUpdate,
      releaseNotes: releaseNotes,
      currentBuildNumber: currentBuildNumber,
      currentVersionName: currentVersionName,
      isUpdateAvailable: isUpdateAvailable,
    );
  }

  /// Converts the update metadata back to a Map structure
  Map<String, dynamic> toMap() {
    return {
      'latest_build_number': latestBuildNumber,
      'latest_version_name': latestVersionName,
      'apk_url': apkUrl,
      'sha256': sha256,
      'force_update': forceUpdate,
      'release_notes': releaseNotes,
    };
  }

  @override
  List<Object?> get props => [
        latestBuildNumber,
        latestVersionName,
        apkUrl,
        sha256,
        forceUpdate,
        releaseNotes,
        currentBuildNumber,
        currentVersionName,
        isUpdateAvailable,
      ];
}
