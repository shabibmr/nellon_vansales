import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/utils/stock_rules.dart';
import 'package:van_sales/ui/core/utils/error_mapper.dart';

void main() {
  group('userFacingMessage', () {
    test('returns fallback for null or empty errors', () {
      expect(userFacingMessage(null), equals('Something went wrong'));
      expect(
        userFacingMessage(null, fallback: 'Custom error'),
        equals('Custom error'),
      );
      expect(userFacingMessage(''), equals('Something went wrong'));
      expect(
        userFacingMessage('', fallback: 'Custom error'),
        equals('Custom error'),
      );
    });

    test('maps InsufficientStockException correctly', () {
      const exc = InsufficientStockException(
        itemId: 'item-1',
        itemName: 'Test Product',
        available: 2,
        requested: 5,
      );
      expect(
        userFacingMessage(exc),
        equals(
          'Cannot fulfill 5 unit(s) of "Test Product" — only 2 available.',
        ),
      );
    });

    test('maps SocketException and TimeoutException correctly', () {
      expect(
        userFacingMessage(const SocketException('Failed host lookup')),
        equals(
          'Network connection error. Please check your internet connection.',
        ),
      );
      expect(
        userFacingMessage(TimeoutException('Timeout')),
        equals('Operation timed out. Please try again.'),
      );
    });

    test('maps DioException types correctly', () {
      final reqOptions = RequestOptions(path: '/test');

      final timeoutDio = DioException(
        requestOptions: reqOptions,
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        userFacingMessage(timeoutDio),
        equals('Connection timed out. Please try again.'),
      );

      final connErrorDio = DioException(
        requestOptions: reqOptions,
        type: DioExceptionType.connectionError,
      );
      expect(
        userFacingMessage(connErrorDio),
        equals(
          'Network connection error. Please check your internet connection.',
        ),
      );

      final serverErrorDio = DioException(
        requestOptions: reqOptions,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: reqOptions,
          statusCode: 500,
          data: null,
        ),
      );
      expect(
        userFacingMessage(serverErrorDio),
        equals('Server error (500). Please try again later.'),
      );

      final zohoBodyDio = DioException(
        requestOptions: reqOptions,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: reqOptions,
          statusCode: 400,
          data: {'message': 'Invalid customer ID'},
        ),
      );
      expect(userFacingMessage(zohoBodyDio), equals('Invalid customer ID'));
    });

    test('strips Exception: and DioException prefixes from raw strings', () {
      expect(
        userFacingMessage(Exception('Invalid invoice number')),
        equals('Invalid invoice number'),
      );
      expect(
        userFacingMessage('Exception: Something went wrong in backend'),
        equals('Something went wrong in backend'),
      );
      expect(
        userFacingMessage('DioException [unknown]: Network request failed'),
        equals('Network request failed'),
      );
      expect(
        userFacingMessage(
          'DioException [bad response]: Exception: Failed: Bad credentials',
        ),
        equals('Bad credentials'),
      );
    });

    test('returns fallback if stripping leaves an empty string', () {
      expect(
        userFacingMessage('DioException [unknown]: '),
        equals('Something went wrong'),
      );
      expect(
        userFacingMessage('Exception: ', fallback: 'Failed to process'),
        equals('Failed to process'),
      );
    });
  });
}
