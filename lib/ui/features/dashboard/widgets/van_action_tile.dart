import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';

/// Premium quick-action tile for dashboard panels (Operations, Reports, sheets).
///
/// Supports a horizontal **list** layout and a vertical **grid** card layout,
/// both sharing the same accent color language, icon treatment, and elevation.
class VanActionTile extends StatelessWidget {
  /// Header text outlining the action.
  final String title;

  /// Supporting description under the title.
  final String subtitle;

  /// Icon representing the action.
  final IconData icon;

  /// Accent color for icon badge, border wash, and highlights.
  final Color color;

  /// Callback fired when the tile body is tapped.
  final VoidCallback onTap;

  /// When true, renders a vertical card for multi-column grids.
  final bool isGrid;

  /// Optional trailing action icon (defaults to a forward arrow).
  /// Use [Icons.add_rounded] on Operations to create a new voucher.
  final IconData actionIcon;

  /// Optional separate handler for the trailing action chip.
  /// When null, the chip is decorative and the whole tile uses [onTap].
  final VoidCallback? onActionTap;

  /// Tooltip for the trailing action (shown when [onActionTap] is set).
  final String? actionTooltip;

  /// When false, the tile renders dimmed and taps route to [onBlocked]
  /// instead of [onTap]/[onActionTap] (orders-only session gating).
  final bool enabled;

  /// Handler fired on tap when [enabled] is false (e.g. shows a snackbar
  /// explaining why the action is unavailable). Falls back to [onTap] when
  /// null so the tile always remains tappable.
  final VoidCallback? onBlocked;

  const VanActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isGrid = false,
    this.actionIcon = Icons.arrow_forward_rounded,
    this.onActionTap,
    this.actionTooltip,
    this.enabled = true,
    this.onBlocked,
  });

  VoidCallback get _effectiveOnTap => enabled ? onTap : (onBlocked ?? onTap);
  VoidCallback get _effectiveOnActionTap =>
      enabled ? (onActionTap ?? onTap) : (onBlocked ?? onTap);

  Color _surface(bool isDark) =>
      isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
  Color _primaryText(bool isDark) =>
      isDark ? AppTheme.darkText : AppTheme.lightText;
  Color _secondaryText(bool isDark) =>
      isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
  Color _border(bool isDark) =>
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  List<BoxShadow> _shadow(bool isDark) => isDark
      ? const []
      : [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tile = isGrid
        ? _buildGridCard(isDark)
        : _buildListTile(isDark);
    final labeled = Semantics(
      button: true,
      enabled: enabled,
      label: title,
      hint: subtitle,
      child: tile,
    );
    if (enabled) return labeled;
    return Opacity(opacity: 0.45, child: labeled);
  }

  // ── List layout ──────────────────────────────────────────────────────────

  Widget _buildListTile(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border(isDark)),
        boxShadow: _shadow(isDark),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withValues(alpha: isDark ? 0.14 : 0.08),
            _surface(isDark),
          ],
          stops: const [0.0, 0.22],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              color: color,
            ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _effectiveOnTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                    child: Row(
                      children: [
                        _IconBadge(
                          icon: icon,
                          color: color,
                          size: 24,
                          padding: 12,
                          radius: 14,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5,
                                  letterSpacing: -0.2,
                                  color: _primaryText(isDark),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: _secondaryText(isDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _ActionChip(
                  icon: actionIcon,
                  color: color,
                 
                  onTap: _effectiveOnActionTap,
                  tooltip: actionTooltip,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grid layout ──────────────────────────────────────────────────────────

  Widget _buildGridCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? color.withValues(alpha: 0.28)
              : color.withValues(alpha: 0.18),
        ),
        boxShadow: _shadow(isDark),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.22 : 0.12),
            _surface(isDark),
            _surface(isDark),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: -18,
            right: -18,
            child: IgnorePointer(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: isDark ? 0.28 : 0.16),
                      color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _effectiveOnTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _IconBadge(
                      icon: icon,
                      color: color,
                      size: 28,
                      padding: 13,
                      radius: 16,
                      filled: true,
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            letterSpacing: -0.25,
                            color: _primaryText(isDark),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: _secondaryText(isDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _ActionChip(
              icon: actionIcon,
              color: color,
              compact: true,
              onTap: _effectiveOnActionTap,
              tooltip: actionTooltip,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded square icon container with a soft gradient wash.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double padding;
  final double radius;
  final bool filled;

  const _IconBadge({
    required this.icon,
    required this.color,
    required this.size,
    required this.padding,
    required this.radius,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = filled ? Colors.white : color;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: filled
              ? [
                  Color.lerp(color, Colors.white, 0.12)!,
                  color,
                  Color.lerp(color, Colors.black, 0.12)!,
                ]
              : [
                  color.withValues(alpha: 0.16),
                  color.withValues(alpha: 0.08),
                ],
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(icon, color: iconColor, size: size),
    );
  }
}

/// Circular trailing action chip (arrow, +, etc.).
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool compact;
  final VoidCallback? onTap;
  final String? tooltip;

  const _ActionChip({
    required this.icon,
    required this.color,
    this.compact = false,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Slightly larger when showing a create (+) action.
    final isAdd = icon == Icons.add_rounded || icon == Icons.add;
    final dim = compact
        ? (isAdd ? 36.0 : 28.0)
        : (isAdd ? 42.0 : 32.0);
    final iconSize = compact
        ? (isAdd ? 22.0 : 14.0)
        : (isAdd ? 26.0 : 16.0);

    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: dim,
          height: dim,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isAdd
                ? color.withValues(alpha: isDark ? 0.28 : 0.16)
                : color.withValues(alpha: isDark ? 0.18 : 0.10),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.40 : 0.22),
              width: isAdd ? 1.5 : 1,
            ),
            boxShadow: isAdd && !isDark
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );

    if (tooltip == null || onTap == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
