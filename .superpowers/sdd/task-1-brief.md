### Task 1: Domain model, label helper, and tests

**Files:**
- Create: `lib/domain/models/print_settings.dart`
- Create: `lib/domain/utils/supervisor_label.dart`
- Create: `test/print_settings_test.dart`

**Interfaces:**
- Produces: `PrintSettings.fallbackSupervisorPhone`, `PrintSettings.fromMap`, `PrintSettings.resolvedPhone`, `formatSupervisorLine(String phone)`

- [ ] **Step 1: Write failing tests**

```dart
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
```

- [ ] **Step 2: Run tests (expect FAIL — missing types)**

Run: `flutter test test/print_settings_test.dart`

- [ ] **Step 3: Implement model + helper**

`lib/domain/models/print_settings.dart`:

```dart
import 'package:equatable/equatable.dart';

class PrintSettings extends Equatable {
  /// Last known hardcoded invoice footer number. Used only when Firestore
  /// and cache have no value so vans never print a blank supervisor line.
  static const String fallbackSupervisorPhone = '+971 501880810';

  final String supervisorPhone;

  const PrintSettings({required this.supervisorPhone});

  String get resolvedPhone =>
      supervisorPhone.trim().isEmpty ? fallbackSupervisorPhone : supervisorPhone.trim();

  factory PrintSettings.fromMap(Map<String, dynamic> map) {
    return PrintSettings(
      supervisorPhone: (map['supervisor_phone'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {'supervisor_phone': supervisorPhone};

  @override
  List<Object?> get props => [supervisorPhone];
}
```

`lib/domain/utils/supervisor_label.dart`:

```dart
String formatSupervisorLine(String phone) {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.toLowerCase().startsWith('supervisor')) return trimmed;
  return 'Supervisor : $trimmed';
}
```

Move the prefix logic out of `SharedPdfTemplate.buildFooter` later (Task 4) so PDF and thermal share this helper.

- [ ] **Step 4: Run tests (expect PASS)**

Run: `flutter test test/print_settings_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/print_settings.dart lib/domain/utils/supervisor_label.dart test/print_settings_test.dart
git commit -m "Add PrintSettings model for Firestore supervisor phone."
```

---

