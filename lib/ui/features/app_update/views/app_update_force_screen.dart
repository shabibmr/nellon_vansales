import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../../domain/models/app_update_info.dart';
import 'app_update_panel.dart';

/// Full-screen blocker used when [AppUpdateInfo.forceUpdate] is true.
///
/// Replaces the rest of the app so login/dashboard are not reachable.
class AppUpdateForceScreen extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateForceScreen({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('app_update_force_screen'),
        backgroundColor: AppTheme.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: AppUpdatePanel(updateInfo: updateInfo),
                ),
                const Spacer(),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppLogo(size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Van Sales • Required update',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
