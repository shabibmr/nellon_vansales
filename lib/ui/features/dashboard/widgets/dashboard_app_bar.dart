import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../ui/core/extensions/org_context_extension.dart';
import '../../../../ui/core/theme/app_theme.dart';
import '../../../../ui/core/widgets/app_logo.dart';
import '../../profile/views/user_profile_page.dart';
import '../../settings/views/settings_page.dart';
import '../../sync/bloc/sync_bloc.dart';
import 'dashboard_navigation_helpers.dart';

class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int currentIndex;
  final bool isWideScreen;

  const DashboardAppBar({
    super.key,
    required this.currentIndex,
    required this.isWideScreen,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: isWideScreen
          ? Text(
              switch (currentIndex) {
                0 => 'Customers & Routes',
                1 => 'Analytics & Dashboard',
                2 => 'Operations Panel',
                3 => 'Reports & Statements',
                _ => 'Dashboard',
              },
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            )
          : Row(
              children: [
                const AppLogo(size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.org.companyName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      actions: [
        BlocBuilder<SyncBloc, SyncState>(
          builder: (context, syncState) {
            final isSyncing = syncState.isSyncing;
            final hasPending = syncState.pendingCount > 0;
            final syncColor = isSyncing
                ? AppTheme.primaryIndigo
                : (hasPending
                      ? AppTheme.warningAmber
                      : AppTheme.successEmerald);

            final syncLabel = isSyncing
                ? 'Syncing. Tap to open Sync Masters'
                : (hasPending
                      ? '${syncState.pendingCount} items pending. Tap to open Sync Masters'
                      : 'All synced. Tap to open Sync Masters');
            return Tooltip(
              message: syncLabel,
              child: Semantics(
                button: true,
                label: syncLabel,
                child: InkWell(
                onTap: () => DashboardNavHelpers.showMastersSyncPage(context),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: syncColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 72),
                        child: Text(
                          isSyncing
                              ? 'Syncing'
                              : (hasPending
                                    ? '${syncState.pendingCount} Pending'
                                    : 'Synced'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: syncColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        isSyncing
                            ? Icons.sync_outlined
                            : Icons.cloud_done_outlined,
                        size: 15,
                        color: syncColor,
                      ),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'My Profile',
          icon: const Icon(Icons.person_outline),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UserProfilePage(),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'Printer & Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsPage(),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
