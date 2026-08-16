import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Severity level for a log line, mirroring common logging framework conventions.
enum LogLevel { debug, info, warning, error }

/// Minimal structured logger wrapping [debugPrint] and forwarding to [FirebaseCrashlytics].
///
/// Every line is tagged with a level and a subsystem tag (e.g. "Sync",
/// "ZohoApi", "Licensing") so logs can be filtered/scanned, and every message
/// is run through [_sanitize] to strip credential-shaped substrings before
/// they ever reach the console or Crashlytics logs — Dio exception messages can otherwise embed
/// request URLs/bodies that carry OAuth tokens or client secrets.
class AppLogger {
  const AppLogger._();

  static void debug(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  static void warning(String tag, String message) =>
      _log(LogLevel.warning, tag, message);

  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      _log(
        LogLevel.error,
        tag,
        message,
        error: error,
        stackTrace: stackTrace,
      );

  /// Sets the user identifier in Crashlytics reports.
  static Future<void> setUserIdentifier(String identifier) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(identifier);
    } catch (_) {}
  }

  /// Sets custom diagnostic key-value pairs in Crashlytics reports.
  static Future<void> setCustomKey(String key, Object value) async {
    try {
      await FirebaseCrashlytics.instance.setCustomKey(key, value);
    } catch (_) {}
  }

  /// Explicitly records a non-fatal or fatal error with custom context in Crashlytics.
  static Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      final sanitizedReason = reason != null ? _sanitize(reason) : null;
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: sanitizedReason,
        fatal: fatal,
      );
    } catch (_) {}
  }

  static void _log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final sanitized = _sanitize(message);
    debugPrint('[${level.name.toUpperCase()}] [$tag] $sanitized');

    // Resilient Crashlytics breadcrumb and error reporting
    try {
      FirebaseCrashlytics.instance.log(
        '[${level.name.toUpperCase()}] [$tag] $sanitized',
      );

      if (level == LogLevel.error) {
        FirebaseCrashlytics.instance.recordError(
          error ?? Exception('[$tag] $sanitized'),
          stackTrace,
          reason: '[$tag] $sanitized',
          fatal: false,
        );
      }
    } catch (_) {
      // Ignored if Firebase is not initialized or in unsupported test environments
    }
  }

  /// Strips known credential-shaped substrings (OAuth tokens, client
  /// secrets, refresh tokens) from a log message before it's emitted.
  static String _sanitize(String message) {
    var sanitized = message;
    for (final pattern in _secretPatterns) {
      sanitized = sanitized.replaceAllMapped(
        pattern,
        (m) => '${m.group(1)}[REDACTED]',
      );
    }
    return sanitized;
  }

  static final List<RegExp> _secretPatterns = [
    RegExp(r'(Zoho-oauthtoken\s+)\S+', caseSensitive: false),
    RegExp(r'(Bearer\s+)\S+', caseSensitive: false),
    RegExp(
      r'("?(?:client_secret|refresh_token|access_token)"?\s*[:=]\s*"?)[^",\s}]+',
      caseSensitive: false,
    ),
  ];
}
