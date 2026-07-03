import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../ui/core/theme/app_theme.dart';

/// A premium responsive analytic metrics card.
///
/// Houses key performance indicators (KPIs) like total sales, collections,
/// expenses, or completed deliveries. Includes clean spacing, custom borders,
/// and a distinctive top-right vector status icon overlay.
class VanMetricCard extends StatelessWidget {
  /// Header label text indicating the category metric.
  final String title;

  /// The formatted numerical or currency string value.
  final String value;

  /// The vector symbol representing this metric.
  final IconData icon;

  /// Signature highlight color applied to the icon.
  final Color color;

  /// Visual theme context flag.
  final bool isDark;

  /// Whether to render with glassmorphism blur effect.
  final bool isGlass;

  /// Creates a new [VanMetricCard] widget.
  const VanMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
    this.isGlass = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isGlass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.glassBorder, width: 1),
            ),
            child: _cardContent(
              titleColor: AppTheme.glassTextSecondary,
              valueColor: AppTheme.glassText,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: _cardContent(
        titleColor: isDark
            ? AppTheme.darkTextSecondary
            : AppTheme.lightTextSecondary,
        valueColor: isDark ? AppTheme.darkText : AppTheme.lightText,
      ),
    );
  }

  Widget _cardContent({required Color titleColor, required Color valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, color: color, size: 18),
          ],
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
