import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../cubit/app_update_cubit.dart';
import '../cubit/app_update_state.dart';
import 'app_update_dialog.dart';

/// Bottom sheet modal for Developer Mode allowing channel switching between Production and Beta.
class DeveloperChannelSheet extends StatefulWidget {
  const DeveloperChannelSheet({super.key});

  /// Displays the developer channel switcher modal
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<AppUpdateCubit>(),
        child: const DeveloperChannelSheet(),
      ),
    );
  }

  @override
  State<DeveloperChannelSheet> createState() => _DeveloperChannelSheetState();
}

class _DeveloperChannelSheetState extends State<DeveloperChannelSheet> {
  late String _selectedChannel;

  @override
  void initState() {
    super.initState();
    _selectedChannel = context.read<AppUpdateCubit>().activeChannel;
  }

  void _onChannelChanged(String? channel) async {
    if (channel == null || channel == _selectedChannel) return;
    setState(() {
      _selectedChannel = channel;
    });
    await context.read<AppUpdateCubit>().switchChannel(channel);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<AppUpdateCubit>();
    final state = cubit.state;
    final isBeta = _selectedChannel == 'beta';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warningAmber.withAlpha(51),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.developer_mode_rounded,
                    color: AppTheme.warningAmber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Developer Mode: OTA Channel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                      ),
                      Text(
                        'Select update stream for this device',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.darkTextSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Production Channel Card
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onChannelChanged('production'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: !_isBeta(context) ? AppTheme.primaryIndigo.withAlpha(38) : AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: !_isBeta(context) ? AppTheme.primaryIndigo : AppTheme.glassBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      !_isBeta(context)
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: !_isBeta(context) ? AppTheme.primaryIndigo : AppTheme.darkTextSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Production Channel (Default)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Stable builds for sales field users (/nellon/)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.darkTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Beta Channel Card
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onChannelChanged('beta'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isBeta ? AppTheme.warningAmber.withAlpha(38) : AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBeta ? AppTheme.warningAmber : AppTheme.glassBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBeta
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isBeta ? AppTheme.warningAmber : AppTheme.darkTextSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Beta / Testing Channel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.warningAmber,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Staging builds from test folder (/nellon/test/)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.darkTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Channel Status Display Card
            if (state is AppUpdateChecking)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryIndigo),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Checking ${_selectedChannel.toUpperCase()} channel for releases...',
                      style: const TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
                    ),
                  ],
                ),
              )
            else if (state is AppUpdateAvailable)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.successEmerald.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.successEmerald),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.new_releases_outlined, color: AppTheme.successEmerald, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Update Available: v${state.updateInfo.latestVersionName}+${state.updateInfo.latestBuildNumber}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Installed: v${state.updateInfo.currentVersionName}+${state.updateInfo.currentBuildNumber}  ➔  Latest: v${state.updateInfo.latestVersionName}+${state.updateInfo.latestBuildNumber}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.darkTextSecondary),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.successEmerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.system_update_rounded, size: 16),
                        label: const Text('Open Update Dialog & Install'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          AppUpdateDialog.show(context, state.updateInfo);
                        },
                      ),
                    ),
                  ],
                ),
              )
            else if (state is AppUpdateUpToDate)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.infoSky.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.infoSky.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppTheme.infoSky, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'App is up to date',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Installed: v${state.updateInfo.currentVersionName}+${state.updateInfo.currentBuildNumber} (Latest on ${_selectedChannel.toUpperCase()}: v${state.updateInfo.latestVersionName}+${state.updateInfo.latestBuildNumber})',
                            style: const TextStyle(fontSize: 11, color: AppTheme.darkTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (state is AppUpdateError)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRose.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.errorRose),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorRose, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.message,
                        style: const TextStyle(fontSize: 12, color: AppTheme.errorRose),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Check for updates button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isBeta ? AppTheme.warningAmber : AppTheme.primaryIndigo,
                foregroundColor: isBeta ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Check for Updates on Selected Channel'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final nav = Navigator.of(context);
                await context.read<AppUpdateCubit>().checkForUpdate();
                if (!context.mounted) return;
                final currentState = context.read<AppUpdateCubit>().state;
                if (currentState is AppUpdateAvailable) {
                  nav.pop();
                  AppUpdateDialog.show(context, currentState.updateInfo);
                } else if (currentState is AppUpdateUpToDate) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Up to date: v${currentState.updateInfo.currentVersionName}+${currentState.updateInfo.currentBuildNumber} is the latest on ${_selectedChannel.toUpperCase()} channel.',
                      ),
                      backgroundColor: AppTheme.darkSurface,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (currentState is AppUpdateError) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(currentState.message),
                      backgroundColor: AppTheme.errorRose,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isBeta(BuildContext context) => _selectedChannel == 'beta';
}
