import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/print_settings.dart';
import 'package:van_sales/domain/utils/supervisor_label.dart';

void main() {
  group('PrintSettings.fromMap', () {
    test('reads supervisor_phone', () {
      final settings = PrintSettings.fromMap({
        'supervisor_phone': ' +971 50 111 2222 ',
      });
      expect(settings.supervisorPhone, '+971 50 111 2222');
    });

    test('empty or missing field yields empty phone', () {
      expect(PrintSettings.fromMap({}).supervisorPhone, '');
      expect(PrintSettings.fromMap({'supervisor_phone': '  '}).supervisorPhone, '');
    });

    test('resolvedPhone uses fallback when empty', () {
      expect(
        const PrintSettings(supervisorPhone: '').resolvedPhone,
        PrintSettings.fallbackSupervisorPhone,
      );
      expect(
        const PrintSettings(supervisorPhone: '+971 50 000 0000').resolvedPhone,
        '+971 50 000 0000',
      );
    });
  });

  group('formatSupervisorLine', () {
    test('prefixes Supervisor when the value is a phone', () {
      expect(
        formatSupervisorLine('+971 501880810'),
        'Supervisor : +971 501880810',
      );
    });

    test('does not double-prefix an already labeled line', () {
      expect(
        formatSupervisorLine('Supervisor : +971 501880810'),
        'Supervisor : +971 501880810',
      );
    });
  });
}
