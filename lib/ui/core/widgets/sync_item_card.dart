import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Card layout shared by master-data and queue-item rows in the sync screen.
/// Provides the icon badge + title/subtitle + trailing widget structure.
class SyncItemCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// When set, replaces [subtitle] with a custom widget (e.g. pill+timestamp row).
  final Widget? subtitleWidget;
  final Color accentColor;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool hasError;

  const SyncItemCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleWidget,
    required this.accentColor,
    required this.trailing,
    this.onTap,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError ? AppTheme.errorRose.withAlpha(120) : borderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(isDark ? 50 : 30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    subtitleWidget ??
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
