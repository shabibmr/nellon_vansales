import 'package:flutter/material.dart';

/// Brand mark for Van Sales Pro / Nellon.
///
/// Renders [assets/images/app_logo.png] at a fixed [size] with optional
/// rounded clip. Use [showShadow] on large hero surfaces (login).
class AppLogo extends StatelessWidget {
  /// Edge length of the square logo in logical pixels.
  final double size;

  /// Soft drop shadow under the mark (login / splash heroes).
  final bool showShadow;

  /// When true, clips to a rounded square matching the asset’s icon shape.
  final bool rounded;

  /// Asset path override (defaults to the app brand logo).
  final String assetPath;

  static const String defaultAssetPath = 'assets/images/app_logo.png';

  const AppLogo({
    super.key,
    this.size = 40,
    this.showShadow = false,
    this.rounded = true,
    this.assetPath = defaultAssetPath,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.local_shipping_rounded,
          size: size * 0.72,
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );

    if (rounded) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: image,
      );
    }

    if (!showShadow) return image;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: image,
    );
  }
}
