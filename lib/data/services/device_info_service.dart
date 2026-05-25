import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Holds flattened details about the target mobile device and app version.
class DeviceDetails {
  final String id;
  final String model;
  final String os;
  final String osVersion;
  final String appVersion;

  const DeviceDetails({
    required this.id,
    required this.model,
    required this.os,
    required this.osVersion,
    required this.appVersion,
  });
}

/// Service wrapping system APIs to resolve machine and bundle release details.
class DeviceInfoService {
  final DeviceInfoPlugin _deviceInfoPlugin;

  DeviceInfoService({DeviceInfoPlugin? deviceInfoPlugin})
      : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  /// Collects, maps, and returns standard device characteristics and active application version numbers.
  Future<DeviceDetails> getDeviceDetails() async {
    String deviceId = 'unknown_device_id';
    String model = 'unknown_device_model';
    String os = 'Android';
    String osVersion = 'unknown_os_version';
    String appVersion = '1.0.0';

    // Retrieve bundle version details if running on a real app context
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {}

    // Resolve hardware level unique identifier and model signatures
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        deviceId = androidInfo.id;
        model = androidInfo.model;
        os = 'Android';
        osVersion = androidInfo.version.release;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios_id';
        model = iosInfo.utsname.machine;
        os = 'iOS';
        osVersion = iosInfo.systemVersion;
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfoPlugin.macOsInfo;
        deviceId = macInfo.systemGUID ?? 'unknown_mac_id';
        model = macInfo.model;
        os = 'macOS';
        osVersion = macInfo.osRelease;
      } else if (Platform.isWindows) {
        final winInfo = await _deviceInfoPlugin.windowsInfo;
        deviceId = winInfo.deviceId;
        model = winInfo.computerName;
        os = 'Windows';
        osVersion = winInfo.displayVersion;
      }
    } catch (_) {
      // Graceful degradation when running on custom platform configurations or unit tests
    }

    return DeviceDetails(
      id: deviceId,
      model: model,
      os: os,
      osVersion: osVersion,
      appVersion: appVersion,
    );
  }
}
