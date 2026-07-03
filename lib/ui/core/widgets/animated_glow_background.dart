import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_cubit.dart';

/// A subtle, app-wide animated backdrop of slowly drifting "glow blobs".
///
/// Renders a single shared [AnimationController] driven [CustomPaint] layer behind
/// [child]. A handful of large, blurred radial-gradient orbs float along slow Lissajous
/// paths and gently breathe, giving every screen a calm, living background without ever
/// competing with the foreground content.
///
/// Mounted once via `MaterialApp.builder` so the whole app shares one controller. The
/// blob palette and base fill track the active [themeMode]. When the platform requests
/// reduced motion the animation holds a single static frame.
class AnimatedGlowBackground extends StatefulWidget {
  /// The active application theme, used to pick the base fill and blob palette.
  final AppThemeMode themeMode;

  /// The application content rendered on top of the animated layer.
  final Widget child;

  /// Creates an [AnimatedGlowBackground].
  const AnimatedGlowBackground({
    super.key,
    required this.themeMode,
    required this.child,
  });

  @override
  State<AnimatedGlowBackground> createState() => _AnimatedGlowBackgroundState();
}

class _AnimatedGlowBackgroundState extends State<AnimatedGlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  Widget build(BuildContext context) {
    // Respect the OS "reduce motion" setting: hold a static frame instead of animating.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _GlowBackgroundPainter(
                  t: _controller.value,
                  themeMode: widget.themeMode,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Immutable description of one drifting orb.
class _Blob {
  /// Resting position as a fraction of the canvas size.
  final Offset base;

  /// Drift amplitude as a fraction of the canvas size.
  final Offset amplitude;

  /// Blob radius as a fraction of the canvas's shortest side.
  final double radius;

  /// Phase offsets (in turns) for the x and y motion.
  final double phaseX;
  final double phaseY;

  /// Core color of the orb (alpha encodes its peak strength).
  final Color color;

  const _Blob({
    required this.base,
    required this.amplitude,
    required this.radius,
    required this.phaseX,
    required this.phaseY,
    required this.color,
  });
}

class _GlowBackgroundPainter extends CustomPainter {
  /// Normalized animation position in `[0, 1)`.
  final double t;
  final AppThemeMode themeMode;

  _GlowBackgroundPainter({required this.t, required this.themeMode});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Base fill — matches what the scaffold used to provide for each theme.
    _paintBase(canvas, rect);

    // 2. Drifting blobs.
    final shortest = size.shortestSide;
    for (final blob in _blobsFor(themeMode)) {
      // Slow Lissajous drift; y uses a different frequency so paths never repeat tightly.
      final dx = blob.amplitude.dx * math.sin((t + blob.phaseX) * 2 * math.pi);
      final dy =
          blob.amplitude.dy * math.cos((t + blob.phaseY) * 1.4 * math.pi);
      final center = Offset(
        (blob.base.dx + dx) * size.width,
        (blob.base.dy + dy) * size.height,
      );

      // Gentle "breathe" on radius and opacity, out of phase per blob.
      final breathe = 0.5 + 0.5 * math.sin((t + blob.phaseX) * 2 * math.pi);
      final radius = shortest * blob.radius * (0.9 + 0.2 * breathe);
      final opacity = 0.75 + 0.25 * breathe;

      final core = blob.color.withValues(alpha: blob.color.a * opacity);
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          core,
          core.withValues(alpha: 0.0),
        ])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintBase(Canvas canvas, Rect rect) {
    final Paint base = Paint();
    switch (themeMode) {
      case AppThemeMode.light:
        base.color = AppTheme.lightBackground;
        canvas.drawRect(rect, base);
      case AppThemeMode.dark:
        base.color = AppTheme.darkBackground;
        canvas.drawRect(rect, base);
      case AppThemeMode.glass:
        // Reuse the original glass gradient so nothing visually regresses.
        base.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.glassBackground1,
            AppTheme.glassBackground2,
            Color(0xFF0F2027),
          ],
        ).createShader(rect);
        canvas.drawRect(rect, base);
    }
  }

  List<_Blob> _blobsFor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        // Very faint on light so text stays crisp.
        return const [
          _Blob(
            base: Offset(0.20, 0.18),
            amplitude: Offset(0.05, 0.06),
            radius: 0.55,
            phaseX: 0.0,
            phaseY: 0.3,
            color: Color(0x146366F1), // indigo ~0.08
          ),
          _Blob(
            base: Offset(0.82, 0.30),
            amplitude: Offset(0.06, 0.05),
            radius: 0.50,
            phaseX: 0.35,
            phaseY: 0.7,
            color: Color(0x120EA5E9), // sky ~0.07
          ),
          _Blob(
            base: Offset(0.55, 0.85),
            amplitude: Offset(0.05, 0.05),
            radius: 0.48,
            phaseX: 0.65,
            phaseY: 0.15,
            color: Color(0x1010B981), // emerald ~0.06
          ),
        ];
      case AppThemeMode.dark:
        return const [
          _Blob(
            base: Offset(0.22, 0.20),
            amplitude: Offset(0.06, 0.07),
            radius: 0.58,
            phaseX: 0.0,
            phaseY: 0.3,
            color: Color(0x266366F1), // indigo ~0.15
          ),
          _Blob(
            base: Offset(0.80, 0.28),
            amplitude: Offset(0.07, 0.05),
            radius: 0.52,
            phaseX: 0.4,
            phaseY: 0.75,
            color: Color(0x200EA5E9), // sky ~0.12
          ),
          _Blob(
            base: Offset(0.50, 0.88),
            amplitude: Offset(0.06, 0.06),
            radius: 0.50,
            phaseX: 0.7,
            phaseY: 0.1,
            color: Color(0x267C3AED), // violet ~0.15
          ),
        ];
      case AppThemeMode.glass:
        // Most visible — leans into the premium glass aesthetic.
        return const [
          _Blob(
            base: Offset(0.24, 0.18),
            amplitude: Offset(0.07, 0.08),
            radius: 0.60,
            phaseX: 0.0,
            phaseY: 0.3,
            color: Color(0x3322D3EE), // cyan ~0.20
          ),
          _Blob(
            base: Offset(0.82, 0.30),
            amplitude: Offset(0.08, 0.06),
            radius: 0.55,
            phaseX: 0.4,
            phaseY: 0.75,
            color: Color(0x386366F1), // indigo ~0.22
          ),
          _Blob(
            base: Offset(0.52, 0.88),
            amplitude: Offset(0.07, 0.07),
            radius: 0.52,
            phaseX: 0.7,
            phaseY: 0.1,
            color: Color(0x33A855F7), // magenta/violet ~0.20
          ),
        ];
    }
  }

  @override
  bool shouldRepaint(_GlowBackgroundPainter old) =>
      old.t != t || old.themeMode != themeMode;
}
