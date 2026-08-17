import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/theme/theme_cubit.dart';
import '../../../../ui/core/widgets/app_logo.dart';
import '../../profile/views/user_profile_page.dart';
import '../../settings/views/settings_page.dart';
import '../cubit/dashboard_nav_cubit.dart';
import 'dashboard_navigation_helpers.dart';

class DashboardSidebar extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  final bool isGlass;
  final IconData themeIcon;
  final Color themeColor;
  final String themeTooltip;

  const DashboardSidebar({
    super.key,
    required this.currentIndex,
    required this.isDark,
    required this.isGlass,
    required this.themeIcon,
    required this.themeColor,
    required this.themeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final companyName = context.org.companyName;

    return Container(
      width: 260,
      color: isGlass
          ? AppTheme.glassBackground2.withValues(alpha: 0.8)
          : (isDark ? AppTheme.darkSurface : AppTheme.lightSurface),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  const AppLogo(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          companyName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Van Sales System',
                          style: TextStyle(
                            fontSize: 11,
                            color: isGlass
                                ? AppTheme.glassTextSecondary
                                : (isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 0,
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Customers',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 1,
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 2,
                    icon: Icons.receipt_long_outlined,
                    activeIcon: Icons.receipt_long,
                    label: 'Transactions',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  _buildSidebarNavItem(
                    context: context,
                    currentIndex: currentIndex,
                    index: 3,
                    icon: Icons.assessment_outlined,
                    activeIcon: Icons.assessment,
                    label: 'Reports',
                    isGlass: isGlass,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.search_rounded,
                      color: isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo,
                    ),
                    title: const Text('Global Search', style: TextStyle(fontSize: 13)),
                    onTap: () => DashboardNavHelpers.showGlobalSearchSheet(context, isDark),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(themeIcon, color: themeColor),
                    title: Text(themeTooltip, style: const TextStyle(fontSize: 13)),
                    onTap: () => context.read<ThemeCubit>().toggleTheme(),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.person_outline,
                      color: isGlass
                          ? Colors.cyanAccent
                          : AppTheme.primaryIndigo,
                    ),
                    title: const Text(
                      'My Profile',
                      style: TextStyle(fontSize: 13),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const UserProfilePage(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      Icons.settings_outlined,
                      color: isGlass
                          ? Colors.cyanAccent
                          : AppTheme.primaryIndigo,
                    ),
                    title: const Text(
                      'Printer & Settings',
                      style: TextStyle(fontSize: 13),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required BuildContext context,
    required int currentIndex,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isGlass,
    required bool isDark,
  }) {
    final isSelected = currentIndex == index;
    final activeColor = isGlass ? Colors.cyanAccent : AppTheme.primaryIndigo;
    final inactiveColor = isGlass
        ? AppTheme.glassTextSecondary
        : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary);

    return InkWell(
      onTap: () => context.read<DashboardNavCubit>().setTab(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? (isGlass ? Colors.cyanAccent : (isDark ? AppTheme.darkText : AppTheme.lightText))
                      : inactiveColor,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
