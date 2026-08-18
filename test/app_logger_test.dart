import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/app_logger.dart';
import 'package:van_sales/data/services/debug_file_logger.dart';

void main() {
  group('AppLogger sanitization', () {
    late List<String> captured;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      captured = [];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('redacts a Zoho-oauthtoken header value', () {
      AppLogger.error('Test', 'Authorization: Zoho-oauthtoken abc123.def456');
      expect(captured.single, isNot(contains('abc123.def456')));
      expect(captured.single, contains('[REDACTED]'));
    });

    test('redacts a client_secret field', () {
      AppLogger.error('Test', '{"client_secret": "supersecretvalue"}');
      expect(captured.single, isNot(contains('supersecretvalue')));
      expect(captured.single, contains('[REDACTED]'));
    });

    test('redacts a refresh_token field', () {
      AppLogger.error('Test', 'refresh_token=1000.abcdef.ghijkl');
      expect(captured.single, isNot(contains('1000.abcdef.ghijkl')));
      expect(captured.single, contains('[REDACTED]'));
    });

    test('leaves non-secret messages untouched aside from the log prefix', () {
      AppLogger.error('Test', 'fetchCustomers error: connection refused');
      expect(
        captured.single,
        contains('fetchCustomers error: connection refused'),
      );
    });

    test('tags the level and subsystem in the emitted line', () {
      AppLogger.warning('Sync', 'retrying later');
      expect(captured.single, contains('[WARNING]'));
      expect(captured.single, contains('[Sync]'));
    });

    test('exposes sanitize for telemetry payloads', () {
      expect(
        AppLogger.sanitize('Authorization: Zoho-oauthtoken abc.def'),
        contains('[REDACTED]'),
      );
    });

    test('clips oversized lines before they reach debugPrint', () {
      final huge = 'x' * 5000;
      AppLogger.info('ZohoApi', huge);
      expect(captured, hasLength(1));
      expect(captured.single.length, lessThan(900));
      expect(captured.single, contains('(+'));
      expect(captured.single, contains('chars)'));
      expect(captured.single, isNot(contains(huge)));
    });
  });
}
