import 'package:flutter/material.dart';

/// Circular container holding an icon over a tinted (or solid) background.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool filled;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 20,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: filled ? Colors.white : color, size: size),
    );
  }
}
