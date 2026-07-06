import 'package:flutter/foundation.dart';

/// Severity level for a log line, mirroring common logging framework conventions.
enum LogLevel { debug, info, warning, error }

/// Minimal structured logger wrapping [debugPrint].
///
/// Every line is tagged with a level and a subsystem tag (e.g. "Sync",
/// "ZohoApi", "Licensing") so logs can be filtered/scanned, and every message
/// is run through [_sanitize] to strip credential-shaped substrings before
/// they ever reach the console — Dio exception messages can otherwise embed
/// request URLs/bodies that carry OAuth tokens or client secrets.
class AppLogger {
  const AppLogger._();

  static void debug(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  static void warning(String tag, String message) =>
      _log(LogLevel.warning, tag, message);

  static void error(String tag, String message) =>
      _log(LogLevel.error, tag, message);

  static void _log(LogLevel level, String tag, String message) {
    debugPrint('[${level.name.toUpperCase()}] [$tag] ${_sanitize(message)}');
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
