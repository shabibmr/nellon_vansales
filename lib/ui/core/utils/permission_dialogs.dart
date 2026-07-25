import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';

/// Dialog that offers to open the app's system permission page.
///
/// Use when a runtime permission was denied (especially permanently denied),
/// so the user can enable it manually on Android.
Future<void> showOpenAppSettingsDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Open Settings',
  String cancelLabel = 'Not now',
}) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(
        Icons.settings_applications_outlined,
        color: AppTheme.primaryIndigo,
        size: 32,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(confirmLabel),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryIndigo,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  if (open == true) {
    await openAppSettings();
  }
}

/// Dialog when GPS/location services are switched off at the OS level.
Future<void> showEnableLocationServiceDialog(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(
        Icons.location_off_outlined,
        color: AppTheme.warningAmber,
        size: 32,
      ),
      title: const Text('Location is turned off'),
      content: const Text(
        'GPS / location services are disabled on this device. '
        'Turn them on so the app can capture customer coordinates.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('Open Location Settings'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryIndigo,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  if (open == true) {
    await Geolocator.openLocationSettings();
  }
}

/// Bluetooth permission denied — navigate user to app settings.
Future<void> showBluetoothPermissionSettingsDialog(BuildContext context) {
  return showOpenAppSettingsDialog(
    context,
    title: 'Bluetooth permission needed',
    message:
        'This app needs Bluetooth access to find and print to your thermal '
        'printer. Tap Open Settings, then allow Nearby devices / Bluetooth '
        'for van_sales, and return to the app.',
  );
}

/// Location permission denied — navigate user to app settings.
Future<void> showLocationPermissionSettingsDialog(BuildContext context) {
  return showOpenAppSettingsDialog(
    context,
    title: 'Location permission needed',
    message:
        'This app needs location access to capture GPS coordinates for '
        'customers. Tap Open Settings, then allow Location for van_sales, '
        'and return to the app.',
  );
}

/// Requests [permissions] and, if still not granted, shows Open Settings.
///
/// Returns `true` only when every permission is granted after the request.
Future<bool> ensurePermissions(
  BuildContext context, {
  required List<Permission> permissions,
  required String title,
  required String message,
}) async {
  final statuses = <Permission, PermissionStatus>{};
  for (final p in permissions) {
    statuses[p] = await p.status;
  }

  final needsRequest = statuses.values.any(
    (s) => !s.isGranted && !s.isLimited,
  );
  if (needsRequest) {
    final requested = await permissions.request();
    statuses
      ..clear()
      ..addAll(requested);
  }

  final granted = statuses.values.every((s) => s.isGranted || s.isLimited);
  if (granted) return true;

  if (!context.mounted) return false;
  await showOpenAppSettingsDialog(
    context,
    title: title,
    message: message,
  );
  return false;
}

/// Ensures Android Bluetooth connect/scan runtime permissions.
Future<bool> ensureBluetoothPermissions(BuildContext context) {
  return ensurePermissions(
    context,
    permissions: const [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ],
    title: 'Bluetooth permission needed',
    message:
        'This app needs Bluetooth access to find and print to your thermal '
        'printer. Tap Open Settings, then allow Nearby devices / Bluetooth '
        'for van_sales, and return to the app.',
  );
}

/// Ensures location-when-in-use permission for GPS capture.
Future<bool> ensureLocationPermissions(BuildContext context) {
  return ensurePermissions(
    context,
    permissions: const [Permission.locationWhenInUse],
    title: 'Location permission needed',
    message:
        'This app needs location access to capture GPS coordinates for '
        'customers. Tap Open Settings, then allow Location for van_sales, '
        'and return to the app.',
  );
}
