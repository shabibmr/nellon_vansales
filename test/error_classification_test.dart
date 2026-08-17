import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/error_classification.dart';

void main() {
  group('classifySyncError', () {
    test('connection timeout is transient', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(classifySyncError(error), ErrorCategory.transient);
    });

    test('connection error is transient', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      expect(classifySyncError(error), ErrorCategory.transient);
    });

    test('5xx bad response is transient', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 503,
        ),
      );
      expect(classifySyncError(error), ErrorCategory.transient);
    });

    test('4xx bad response is permanent', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
        ),
      );
      expect(classifySyncError(error), ErrorCategory.permanent);
    });

    test('unknown DioException type is permanent', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.unknown,
      );
      expect(classifySyncError(error), ErrorCategory.permanent);
    });

    test('a plain SocketException-shaped message is transient', () {
      expect(
        classifySyncError(Exception('SocketException: Network unreachable')),
        ErrorCategory.transient,
      );
    });

    test('a validation-shaped message is permanent', () {
      expect(
        classifySyncError(Exception('Invalid customer_id: cannot be blank')),
        ErrorCategory.permanent,
      );
    });
  });

  group('isNetworkFailure', () {
    test('connection and timeout types are network', () {
      expect(
        isNetworkFailure(
          DioException(
            requestOptions: RequestOptions(path: '/invoices'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isTrue,
      );
      expect(
        isNetworkFailure(
          DioException(
            requestOptions: RequestOptions(path: '/invoices'),
            type: DioExceptionType.connectionError,
          ),
        ),
        isTrue,
      );
    });

    test('HTTP 4xx and 5xx are not network', () {
      expect(
        isNetworkFailure(
          DioException(
            requestOptions: RequestOptions(path: '/invoices'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/invoices'),
              statusCode: 400,
            ),
          ),
        ),
        isFalse,
      );
      expect(
        isNetworkFailure(
          DioException(
            requestOptions: RequestOptions(path: '/invoices'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/invoices'),
              statusCode: 503,
            ),
          ),
        ),
        isFalse,
      );
    });

    test('cancelled requests are not reported as Zoho API failures', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/invoices'),
        type: DioExceptionType.cancel,
      );
      expect(isNetworkFailure(error), isFalse);
      expect(shouldReportZohoApiFailure(error), isFalse);
    });

    test('socket-shaped messages are network', () {
      expect(
        isNetworkFailure(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(
        shouldReportZohoApiFailure(Exception('Failed host lookup')),
        isFalse,
      );
    });
  });

  group('humanizeSyncErrorMessage', () {
    test('extracts Zoho message from verbose body= exception', () {
      const raw =
          '[Needs Attention] Exception: Zoho Books Sales Order Sync Failed: '
          'status=400 body={"code":400030,"message":"The location youre trying '
          'to associate with this transaction is inactive. Select an active '
          'location or mark this location as active to associate it."} '
          'error=DioException [bad response]: This exception was thrown because '
          'the response has a status code of 400';
      expect(
        humanizeSyncErrorMessage(raw),
        'The location youre trying to associate with this transaction is '
        'inactive. Select an active location or mark this location as active '
        'to associate it.',
      );
    });

    test('strips category tag from already-friendly message', () {
      expect(
        humanizeSyncErrorMessage(
          '[Needs Attention] The location is inactive.',
        ),
        'The location is inactive.',
      );
    });

    test('reads message from DioException response body', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/salesorders'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/salesorders'),
          statusCode: 400,
          data: {
            'code': 400030,
            'message': 'The location is inactive.',
          },
        ),
      );
      expect(humanizeSyncError(error), 'The location is inactive.');
    });
  });

  group('isFirestorePermissionDenied', () {
    test('matches cloud_firestore permission-denied', () {
      expect(
        isFirestorePermissionDenied(
          Exception(
            '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
          ),
        ),
        isTrue,
      );
    });

    test('does not match a network timeout', () {
      expect(
        isFirestorePermissionDenied(Exception('Network connection timed out')),
        isFalse,
      );
    });
  });
}
