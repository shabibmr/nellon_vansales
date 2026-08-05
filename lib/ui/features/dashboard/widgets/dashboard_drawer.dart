import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/theme/theme_cubit.dart';
import '../../../../ui/core/widgets/app_logo.dart';
import '../../profile/views/user_profile_page.dart';
import '../../settings/views/settings_page.dart';
import 'dashboard_navigation_helpers.dart';

class DashboardDrawer extends StatelessWidget {
  final bool isDark;
  final bool isGlass;
  final IconData themeIcon;
  final Color themeColor;
  final String themeTooltip;

  const DashboardDrawer({
    super.key,
    required this.isDark,
    required this.isGlass,
    required this.themeIcon,
    required this.themeColor,
    required this.themeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: isGlass
          ? AppTheme.glassBackground2
          : (isDark ? AppTheme.darkBackground : AppTheme.lightSurface),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  const AppLogo(size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.org.companyName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.search_rounded,
                color: isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo,
              ),
              title: const Text('Global Database Search'),
              onTap: () {
                Navigator.pop(context);
                DashboardNavHelpers.showGlobalSearchSheet(context, isDark);
              },
            ),
            Semantics(
              button: true,
              label: themeTooltip,
              child: ListTile(
                leading: Icon(themeIcon, color: themeColor),
                title: Text(themeTooltip),
                onTap: () => context.read<ThemeCubit>().toggleTheme(),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.person_outline,
                color: isGlass
                    ? Colors.cyanAccent
                    : AppTheme.primaryIndigo,
              ),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserProfilePage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.settings_outlined,
                color: isGlass
                    ? Colors.cyanAccent
                    : AppTheme.primaryIndigo,
              ),
              title: const Text('Printer & Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
