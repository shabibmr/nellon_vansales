import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../domain/models/user.dart';
import '../cubit/license_cubit.dart';
import '../cubit/license_state.dart';
import '../cubit/server_config_cubit.dart';
import 'license_blocked_screen.dart';

/// Navigation wrapper gating access based on device licensing checks.
///
/// Directs flow:
/// - Auto-provisioning first-time logins.
/// - Displaying blocked layouts if license is disabled/expired.
/// - Propagating remote Zoho server configurations app-wide on validation.
class LicenseGate extends StatefulWidget {
  final User user;
  final Widget child;

  const LicenseGate({super.key, required this.user, required this.child});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  @override
  void initState() {
    super.initState();
    // Kickstart license verification on gate mount
    _triggerCheck();
  }

  @override
  void didUpdateWidget(covariant LicenseGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-verify if the user session changes (e.g. logging out and in with another account)
    if (oldWidget.user.id != widget.user.id) {
      _triggerCheck();
    }
  }

  void _triggerCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LicenseCubit>().checkLicense(widget.user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LicenseCubit, LicenseState>(
      listener: (context, state) {
        if (state is LicenseValid) {
          // Feed the server configuration cubit once the license validates
          context.read<ServerConfigCubit>().setConfig(state.serverConfig);
        } else if (state is LicensePendingFirstLogin) {
          // Frictionless first login auto-registration
          context.read<LicenseCubit>().registerFirstLogin(widget.user);
        }
      },
      child: BlocBuilder<LicenseCubit, LicenseState>(
        builder: (context, state) {
          if (state is LicenseValid) {
            return widget.child;
          }

          if (state is LicenseBlocked) {
            return LicenseBlockedScreen(reason: state.reason);
          }

          if (state is LicenseError) {
            return _buildErrorScreen(state.message);
          }

          // Render loading screen during license check / registration
          final loadingMessage = state is LicensePendingFirstLogin
              ? 'Activating Trial License...'
              : 'Verifying Security License...';
          return _buildLoadingScreen(loadingMessage);
        },
      ),
    );
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryIndigo),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.darkText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait a moment',
              style: TextStyle(
                color: AppTheme.darkTextSecondary.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String errorMsg) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 72,
              color: AppTheme.errorRose,
            ),
            const SizedBox(height: 24),
            const Text(
              'Activation Failure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.darkText,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.errorRose.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                errorMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                context.read<LicenseCubit>().registerFirstLogin(widget.user);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Activation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
