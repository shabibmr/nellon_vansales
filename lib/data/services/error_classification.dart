import 'dart:convert';

import 'package:dio/dio.dart';

/// Whether a failure is worth retrying automatically, or requires a human
/// to fix something (bad data, business-rule rejection) before retrying
/// would ever succeed.
enum ErrorCategory {
  /// Network/connectivity-shaped failures (timeouts, connection errors,
  /// 5xx server errors) — retrying the same request later may succeed.
  transient,

  /// Validation or business-rule rejections (4xx client errors, malformed
  /// payloads) — retrying with the same payload will fail again until the
  /// underlying data is corrected.
  permanent,
}

/// Classifies an error caught while syncing a transaction, so retry UX can
/// distinguish "try again later" from "needs attention" instead of treating
/// every failure identically.
ErrorCategory classifySyncError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return ErrorCategory.transient;
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        // 5xx (server-side) is worth retrying; 4xx (client/validation) is not.
        return statusCode >= 500
            ? ErrorCategory.transient
            : ErrorCategory.permanent;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ErrorCategory.permanent;
    }
  }

  final message = error.toString().toLowerCase();
  if (message.contains('socketexception') ||
      message.contains('timeout') ||
      message.contains('connection') ||
      message.contains('network')) {
    return ErrorCategory.transient;
  }

  return ErrorCategory.permanent;
}

/// Short, user-facing text for a sync failure — prefers Zoho's `message`
/// from the response body over Dio's multi-line status-code boilerplate.
String humanizeSyncError(Object error) {
  if (error is DioException) {
    final fromBody = zohoMessageFromResponseData(error.response?.data);
    if (fromBody != null && fromBody.isNotEmpty) return fromBody;
  }
  return humanizeSyncErrorMessage(error.toString());
}

/// Parses a stored queue [errorMessage] (with optional `[Retryable]` /
/// `[Needs Attention]` tag) into a readable line for the Upload Queue UI.
///
/// Handles both clean messages and older verbose strings that still embed
/// `body={"code":…,"message":"…"}` or a trailing DioException dump.
String humanizeSyncErrorMessage(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return 'Sync failed';

  // Category tags are shown as pills in the UI — drop them from the body.
  s = s.replaceFirst(RegExp(r'^\[(Retryable|Needs Attention)\]\s*'), '');
  s = s.replaceFirst(RegExp(r'^Exception:\s*'), '');

  final fromJson = _zohoMessageFromEmbeddedJson(s);
  if (fromJson != null && fromJson.isNotEmpty) return fromJson;

  // Drop the DioException wall that follows `error=` in older throws.
  final errorEq = s.indexOf(' error=DioException');
  if (errorEq > 0) {
    s = s.substring(0, errorEq).trim();
  } else {
    final dioAt = s.indexOf('DioException');
    if (dioAt > 0) s = s.substring(0, dioAt).trim();
  }

  // Prefer text after the last "Failed: " prefix from ZohoApiClient wrappers.
  final failedAt = s.lastIndexOf('Failed: ');
  if (failedAt >= 0) {
    final tail = s.substring(failedAt + 'Failed: '.length).trim();
    if (tail.isNotEmpty && !tail.startsWith('status=')) {
      s = tail;
    } else if (tail.startsWith('status=')) {
      // status=400 body=… with no parseable message — keep a short summary.
      final statusMatch = RegExp(r'status=(\d+)').firstMatch(tail);
      if (statusMatch != null) {
        return 'Request rejected by Zoho (HTTP ${statusMatch.group(1)})';
      }
    }
  }

  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return 'Sync failed';
  // Cap runaway dumps that still slipped through.
  if (s.length > 280) s = '${s.substring(0, 277)}…';
  return s;
}

/// Reads Zoho Books error envelope `message` from a decoded response body.
String? zohoMessageFromResponseData(dynamic data) {
  if (data == null) return null;
  if (data is String) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return null;
    try {
      return zohoMessageFromResponseData(jsonDecode(trimmed));
    } catch (_) {
      return trimmed;
    }
  }
  if (data is Map) {
    final message = data['message'] ?? data['Message'];
    if (message != null) {
      final text = message.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

String? _zohoMessageFromEmbeddedJson(String text) {
  // body={...} as written by syncSalesOrder debug throws.
  final bodyIdx = text.indexOf('body=');
  if (bodyIdx >= 0) {
    final after = text.substring(bodyIdx + 5).trimLeft();
    if (after.startsWith('{')) {
      final jsonStr = _extractBalancedJsonObject(after);
      if (jsonStr != null) {
        try {
          final msg = zohoMessageFromResponseData(jsonDecode(jsonStr));
          if (msg != null) return msg;
        } catch (_) {}
      }
    }
  }

  // Any embedded "message":"..." (response JSON inlined in the exception).
  final msgMatch = RegExp(
    r'"message"\s*:\s*"((?:\\.|[^"\\])*)"',
  ).firstMatch(text);
  if (msgMatch != null) {
    return _unescapeJsonString(msgMatch.group(1)!);
  }
  return null;
}

/// Returns the leading `{…}` slice with balanced braces, or null.
String? _extractBalancedJsonObject(String source) {
  if (!source.startsWith('{')) return null;
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch == r'\') {
        escape = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(0, i + 1);
    }
  }
  return null;
}

String _unescapeJsonString(String value) {
  try {
    return jsonDecode('"$value"') as String;
  } catch (_) {
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\\', r'\');
  }
}
