import 'package:flutter/material.dart';
import '../extensions/l10n_context_extension.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';

/// App startup and session verification splash screen.
///
/// Displays the application brand mark, title, and an ambient glowing background
/// with a progress bar while [AuthBloc] resolves the cached session.
class AppSplashScreen extends StatelessWidget {
  /// Status caption displayed beneath the progress bar.
  final String? statusText;

  const AppSplashScreen({
    super.key,
    this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient matching login / app theme
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF0F172A),
                        const Color(0xFF1E1E38),
                        const Color(0xFF110E24),
                      ]
                    : [
                        const Color(0xFFEEF2F6),
                        const Color(0xFFE0E7FF),
                        const Color(0xFFEEF2F6),
                      ],
              ),
            ),
          ),

          // Ambient Glow Orbs
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                    blurRadius: 100,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.infoSky.withValues(alpha: 0.15),
                    blurRadius: 90,
                    spreadRadius: 30,
                  ),
                ],
              ),
            ),
          ),

          // Content Layer
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 100, showShadow: true),
                    const SizedBox(height: 24),
                    Text(
                      context.l10n.brandName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.brandSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: AppTheme.primaryIndigo
                              .withValues(alpha: 0.15),
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      statusText ?? context.l10n.verifyingSession,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
