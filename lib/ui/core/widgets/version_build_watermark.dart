import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Small always-on-top corner label showing the running app version + build
/// number, for quick identification during QA / support screenshots.
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
    if (_label == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              _label!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
