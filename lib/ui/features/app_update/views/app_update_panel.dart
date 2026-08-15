import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../domain/models/app_update_info.dart';
import '../cubit/app_update_cubit.dart';
import '../cubit/app_update_state.dart';

/// Shared changelog, progress, error, and action buttons for force screen and optional dialog.
class AppUpdatePanel extends StatelessWidget {
  final AppUpdateInfo updateInfo;
  final VoidCallback? onLater;

  const AppUpdatePanel({
    super.key,
    required this.updateInfo,
    this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppUpdateCubit, AppUpdateState>(
      builder: (context, state) {
        final isDownloading = state is AppUpdateDownloading;
        final isInstalling = state is AppUpdateInstalling;
        final hasError = state is AppUpdateError;
        final progress = (state is AppUpdateDownloading) ? state.progress : 0.0;
        final statusText = (state is AppUpdateDownloading)
            ? state.statusText
            : (state is AppUpdateInstalling)
                ? 'Launching installer...'
                : (state is AppUpdateError)
                    ? state.message
                    : '';
        final showLater = onLater != null &&
            !updateInfo.forceUpdate &&
            !isDownloading &&
            !isInstalling;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo.withAlpha(51),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppTheme.primaryIndigo,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'App Update Available',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${updateInfo.currentVersionName} ➔ v${updateInfo.latestVersionName}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.infoSky,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (updateInfo.releaseNotes.isNotEmpty) ...[
              const Text(
                "What's New:",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkTextSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    updateInfo.releaseNotes,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.darkText,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (isDownloading || isInstalling) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: isDownloading && progress > 0 ? progress : null,
                  minHeight: 8,
                  backgroundColor: AppTheme.darkCard,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryIndigo,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.darkTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
            ] else if (hasError) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.errorRose.withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.errorRose.withAlpha(76)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppTheme.errorRose,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.errorRose,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (updateInfo.forceUpdate) ...[
              const Text(
                'This update is required to continue using the application.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.warningAmber,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showLater)
                  TextButton(
                    onPressed: onLater,
                    child: const Text(
                      'Later',
                      style: TextStyle(color: AppTheme.darkTextSecondary),
                    ),
                  ),
                const SizedBox(width: 8),
                if (!isDownloading && !isInstalling)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      hasError ? Icons.refresh : Icons.cloud_download_outlined,
                      size: 18,
                    ),
                    label: Text(hasError ? 'Retry Update' : 'Update Now'),
                    onPressed: () {
                      context.read<AppUpdateCubit>().startDownloadAndInstall(
                            updateInfo,
                          );
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
