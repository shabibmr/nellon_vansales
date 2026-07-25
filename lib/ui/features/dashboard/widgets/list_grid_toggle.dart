import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';

/// Compact list/grid layout switch for menu-style tabs (Operations, Reports).
class ListGridToggle extends StatelessWidget {
  final bool isGrid;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const ListGridToggle({
    super.key,
    required this.isGrid,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final selectedBg = AppTheme.primaryIndigo.withValues(alpha: 0.12);
    final selectedFg = AppTheme.primaryIndigo;
    final unselectedFg = secondary;

    return Row(
      children: [
        Text(
          isGrid ? 'Grid view' : 'List view',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToggleIcon(
                icon: Icons.view_list_rounded,
                tooltip: 'List view',
                selected: !isGrid,
                selectedBg: selectedBg,
                selectedFg: selectedFg,
                unselectedFg: unselectedFg,
                onTap: () => onChanged(false),
              ),
              _ToggleIcon(
                icon: Icons.grid_view_rounded,
                tooltip: 'Grid view',
                selected: isGrid,
                selectedBg: selectedBg,
                selectedFg: selectedFg,
                unselectedFg: unselectedFg,
                onTap: () => onChanged(true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color selectedBg;
  final Color selectedFg;
  final Color unselectedFg;
  final VoidCallback onTap;

  const _ToggleIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.selectedBg,
    required this.selectedFg,
    required this.unselectedFg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: selected ? selectedFg : unselectedFg,
            ),
          ),
        ),
      ),
    );
  }
}
