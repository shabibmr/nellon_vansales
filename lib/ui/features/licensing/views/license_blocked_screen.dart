import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// A secure, premium screen displayed when a device has been blocked or license has expired.
///
/// Contains no navigation triggers, no menus, and no retry buttons. Designed to be completely
/// secure while maintaining the high aesthetic standard of the application.
class LicenseBlockedScreen extends StatelessWidget {
  final String reason;

  const LicenseBlockedScreen({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Stack(
        children: [
          // Background Gradient Orbs for Sleek Aesthetics
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.errorRose.withValues(alpha: 0.15),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

          // Main Content Layer
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 24.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),

                  // Pulsing Glowing Lock Container
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface.withOpacity(0.6),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.errorRose.withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: AppTheme.errorRose.withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_person_rounded,
                        size: 64,
                        color: AppTheme.errorRose,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Heading
                  const Text(
                    'Access Restricted',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.darkText,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Glassmorphic Detail Card
                  Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF334155).withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          reason,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: Color(0xFF334155), height: 1),
                        const SizedBox(height: 20),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.support_agent_rounded,
                              size: 20,
                              color: AppTheme.darkTextSecondary,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Please contact your administrator.',
                              style: TextStyle(
                                color: AppTheme.darkTextSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Footer security banner
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.security_rounded,
                        size: 16,
                        color: Color(0xFF475569),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Van Sales Pro • Enterprise Security Gate',
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
        ],
      ),
    );
  }
}
