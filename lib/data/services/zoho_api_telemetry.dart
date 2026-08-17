import 'package:dio/dio.dart';

import 'error_classification.dart';

/// Structured snapshot of a Zoho Books/Inventory API failure that is **not**
/// a network/connectivity problem.
class ZohoApiFailureReport {
  const ZohoApiFailureReport({
    required this.method,
    required this.path,
    required this.dioType,
    required this.message,
    required this.source,
    this.statusCode,
    this.zohoCode,
  });

  final String method;
  final String path;
  final String dioType;
  final String message;
  final String source;
  final int? statusCode;
  final String? zohoCode;

  String get crashReason {
    final status = statusCode != null ? ' HTTP $statusCode' : '';
    return 'Zoho API $method $path$status';
  }

  /// Firebase Analytics custom-event parameters (names ≤40 chars, values ≤100).
  Map<String, Object> toAnalyticsParameters() {
    final params = <String, Object>{
      'method': _clip(method, 40),
      'path': _clip(path, 100),
      'dio_type': _clip(dioType, 40),
      'source': _clip(source, 40),
      'message': _clip(message, 100),
    };
    if (statusCode != null) {
      params['status'] = statusCode!;
    }
    if (zohoCode != null && zohoCode!.isNotEmpty) {
      params['zoho_code'] = _clip(zohoCode!, 40);
    }
    return params;
  }
}

/// Builds a report when [error] should be sent to Crashlytics/Analytics.
///
/// Returns `null` for network failures and cancelled requests.
ZohoApiFailureReport? zohoApiFailureReport(
  Object error, {
  String source = 'http',
}) {
  if (!shouldReportZohoApiFailure(error)) return null;

  if (error is DioException) {
    final uri = error.requestOptions.uri;
    return ZohoApiFailureReport(
      method: error.requestOptions.method.toUpperCase(),
      path: _pathOnly(uri),
      dioType: error.type.name,
      message: _messageFor(error),
      source: source,
      statusCode: error.response?.statusCode,
      zohoCode: _zohoCodeFrom(error.response?.data),
    );
  }

  return ZohoApiFailureReport(
    method: 'N/A',
    path: source,
    dioType: 'exception',
    message: _clip(error.toString(), 100),
    source: source,
  );
}

String _pathOnly(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  return _clip(path, 100);
}

String _messageFor(DioException error) {
  final fromBody = zohoMessageFromResponseData(error.response?.data);
  if (fromBody != null && fromBody.isNotEmpty) return _clip(fromBody, 100);
  final human = humanizeSyncError(error);
  if (human.isNotEmpty) return _clip(human, 100);
  return _clip(error.message ?? error.type.name, 100);
}

String? _zohoCodeFrom(dynamic data) {
  if (data is Map && data['code'] != null) {
    return data['code'].toString();
  }
  return null;
}

String _clip(String value, int max) {
  if (value.length <= max) return value;
  return value.substring(0, max);
}
