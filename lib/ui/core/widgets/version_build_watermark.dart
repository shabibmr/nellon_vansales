import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Near-invisible "v{version}+{build}" label pinned to the bottom-right
/// corner of every screen, mounted once via `MaterialApp.builder`.
class VersionBuildWatermark extends StatefulWidget {
  const VersionBuildWatermark({super.key});

  @override
  State<VersionBuildWatermark> createState() => _VersionBuildWatermarkState();
}

class _VersionBuildWatermarkState extends State<VersionBuildWatermark> {
  String? _label;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _label = 'v${info.version}+${info.buildNumber}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) return const SizedBox.shrink();

    final baseColor = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurface;

    return Positioned(
      right: 6,
      bottom: 6 + MediaQuery.paddingOf(context).bottom,
      child: IgnorePointer(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: baseColor.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}
