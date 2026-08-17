import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/zoho_api_telemetry.dart';

void main() {
  group('zohoApiFailureReport', () {
    test('returns null for connection errors', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/invoices'),
        type: DioExceptionType.connectionError,
      );
      expect(zohoApiFailureReport(error), isNull);
    });

    test('captures HTTP 400 Zoho validation errors', () {
      final error = DioException(
        requestOptions: RequestOptions(
          path: '/invoices',
          method: 'POST',
        ),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/invoices'),
          statusCode: 400,
          data: {
            'code': 400030,
            'message': 'The location is inactive.',
          },
        ),
      );

      final report = zohoApiFailureReport(error);
      expect(report, isNotNull);
      expect(report!.method, 'POST');
      expect(report.path, '/invoices');
      expect(report.statusCode, 400);
      expect(report.zohoCode, '400030');
      expect(report.message, 'The location is inactive.');
      expect(report.crashReason, 'Zoho API POST /invoices HTTP 400');
      expect(
        report.toAnalyticsParameters(),
        containsPair('zoho_code', '400030'),
      );
    });

    test('captures HTTP 5xx as a reportable Zoho failure', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/salesorders', method: 'GET'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/salesorders'),
          statusCode: 503,
        ),
      );
      final report = zohoApiFailureReport(error);
      expect(report, isNotNull);
      expect(report!.statusCode, 503);
    });

    test('reports OAuth credential failures that are not Dio', () {
      final report = zohoApiFailureReport(
        Exception('Zoho credentials not configured'),
        source: 'oauth_refresh',
      );
      expect(report, isNotNull);
      expect(report!.source, 'oauth_refresh');
      expect(report.path, 'oauth_refresh');
    });
  });
}
