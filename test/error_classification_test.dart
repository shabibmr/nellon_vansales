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
}
