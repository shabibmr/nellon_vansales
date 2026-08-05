import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/masters_sync_bloc.dart';
import '../bloc/masters_sync_event.dart';
import '../bloc/masters_sync_state.dart';

class MastersSyncHeader extends StatelessWidget {
  final MastersSyncState state;
  final bool isDark;
  final int syncedCount;
  final int totalCount;
  final VoidCallback onLongPressConsole;

  const MastersSyncHeader({
    super.key,
    required this.state,
    required this.isDark,
    required this.syncedCount,
    required this.totalCount,
    required this.onLongPressConsole,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : syncedCount / totalCount;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryIndigo, AppTheme.primaryDarkIndigo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.27),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Master Data',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '$syncedCount of $totalCount synced',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: state.bulkInFlight && progress == 0 ? null : progress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onLongPress: onLongPressConsole,
                  child: ElevatedButton.icon(
                    onPressed: state.bulkInFlight
                        ? null
                        : () => context
                            .read<MastersSyncBloc>()
                            .add(SyncAllRequested()),
                    icon: state.bulkInFlight
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryIndigo,
                            ),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(
                      state.bulkInFlight ? 'Syncing all…' : 'Sync All Masters',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryIndigo,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                      disabledForegroundColor: AppTheme.primaryIndigo,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.bulkSyncStatus != null) ...[
          const SizedBox(height: 16),
          _buildStatusBanner(state, isDark),
        ],
      ],
    );
  }

  Widget _buildStatusBanner(MastersSyncState state, bool isDark) {
    final success = state.bulkSyncSuccess;
    final Color bg = success == true
        ? (isDark
              ? AppTheme.successEmerald.withValues(alpha: 0.16)
              : const Color(0xFFE8F5E9))
        : success == false
        ? (isDark ? AppTheme.errorRose.withValues(alpha: 0.16) : const Color(0xFFFFEBEE))
        : (isDark
              ? AppTheme.primaryIndigo.withValues(alpha: 0.16)
              : const Color(0xFFE8EAF6));
    final Color border = success == true
        ? AppTheme.successEmerald.withValues(alpha: 0.39)
        : success == false
        ? AppTheme.errorRose.withValues(alpha: 0.39)
        : AppTheme.primaryIndigo.withValues(alpha: 0.39);
    final Color fg = success == true
        ? (isDark ? Colors.green[200]! : const Color(0xFF2E7D32))
        : success == false
        ? (isDark ? Colors.red[200]! : const Color(0xFFC62828))
        : (isDark ? Colors.indigo[200]! : AppTheme.primaryIndigo);
    final IconData icon = success == true
        ? Icons.check_circle_rounded
        : success == false
        ? Icons.error_outline_rounded
        : Icons.sync_outlined;
    final Color iconColor = success == true
        ? AppTheme.successEmerald
        : success == false
        ? AppTheme.errorRose
        : AppTheme.primaryIndigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.bulkSyncStatus!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
