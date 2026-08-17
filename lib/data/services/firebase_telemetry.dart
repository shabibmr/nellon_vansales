import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/user.dart';
import 'app_logger.dart';
import 'zoho_api_telemetry.dart';

/// Crashlytics + Analytics facade used by the composition root and Zoho client.
///
/// Every call is fail-open: missing Firebase init (tests, sandbox) is ignored.
class FirebaseTelemetry {
  const FirebaseTelemetry._();

  static const zohoApiFailureEvent = 'zoho_api_failure';

  static FirebaseAnalyticsObserver navigatorObserver() {
    return FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);
  }

  static Future<void> bindUser(User user) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(user.id);
      await FirebaseAnalytics.instance.setUserId(id: user.id);
      if (user.role.isNotEmpty) {
        await FirebaseAnalytics.instance.setUserProperty(
          name: 'user_role',
          value: user.role,
        );
      }
      await FirebaseCrashlytics.instance.setCustomKey('user_role', user.role);
      await FirebaseAnalytics.instance.logLogin(loginMethod: 'phone');
    } catch (_) {}
  }

  static Future<void> clearUser() async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier('');
      await FirebaseAnalytics.instance.setUserId(id: null);
    } catch (_) {}
  }

  /// Records a Zoho Books API failure that is **not** caused by the network.
  static Future<void> reportZohoApiFailure(
    Object error, {
    StackTrace? stackTrace,
    String source = 'http',
  }) async {
    final report = zohoApiFailureReport(error, source: source);
    if (report == null) return;

    final reason = AppLogger.sanitize(report.crashReason);
    final message = AppLogger.sanitize(report.message);

    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCustomKey('zoho_path', report.path);
      await crashlytics.setCustomKey('zoho_method', report.method);
      await crashlytics.setCustomKey('zoho_source', report.source);
      await crashlytics.setCustomKey(
        'zoho_status',
        report.statusCode ?? 0,
      );
      if (report.zohoCode != null) {
        await crashlytics.setCustomKey('zoho_code', report.zohoCode!);
      }
      await crashlytics.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: '$reason: $message',
        fatal: false,
        information: [
          DiagnosticsProperty('method', report.method),
          DiagnosticsProperty('path', report.path),
          DiagnosticsProperty('status', report.statusCode),
          DiagnosticsProperty('zoho_code', report.zohoCode),
          DiagnosticsProperty('dio_type', report.dioType),
          DiagnosticsProperty('source', report.source),
        ],
      );
    } catch (_) {}

    try {
      await FirebaseAnalytics.instance.logEvent(
        name: zohoApiFailureEvent,
        parameters: report.toAnalyticsParameters(),
      );
    } catch (_) {}
  }
}
