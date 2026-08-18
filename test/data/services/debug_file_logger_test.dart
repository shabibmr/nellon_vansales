import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/debug_file_logger.dart';

void main() {
  group('DebugFileLogger.clip', () {
    test('leaves short messages unchanged', () {
      expect(DebugFileLogger.clip('hello', 800), 'hello');
    });

    test('truncates long messages with an omitted-char suffix', () {
      final clipped = DebugFileLogger.clip('a' * 1000, 20);
      expect(clipped.startsWith('aaaaaaaaaaaaaaaaaaaa'), isTrue);
      expect(clipped, contains('(+980 chars)'));
      expect(clipped.length, lessThan(50));
    });
  });
}
