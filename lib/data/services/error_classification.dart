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
