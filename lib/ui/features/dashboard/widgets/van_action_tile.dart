import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';

/// A premium responsive quick-action list tile component.
///
/// Configures a clean layout featuring a colored leading circular badge icon,
/// bold title, descriptive subtitle, and arrow indicator trailing icon.
/// Typically used within dashboard panels to fire operation workflows.
class VanActionTile extends StatelessWidget {
  /// Header text outlining the action.
  final String title;

  /// Details of the enqueued action or background context description.
  final String subtitle;

  /// Vector graphic asset to represent the action.
  final IconData icon;

  /// Primary color used for the leading icon and its background circle overlay.
  final Color color;

  /// Visual theme context flag.
  final bool isDark;

  /// Callback fired when the tile is tapped.
  final VoidCallback onTap;

  /// Creates a new [VanActionTile] widget.
  const VanActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, height: 1.3),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}
