# Review package Task 1
BASE 72603d9e85d2c7f9b0f298f6e540462ef98996b5
HEAD d592b75c30a417d2877174f70f46c85f961f5c6b
## Commits
d592b75 Add PrintSettings model for Firestore supervisor phone.

## Stat
 lib/domain/models/print_settings.dart  | 25 ++++++++++++++++++
 lib/domain/utils/supervisor_label.dart |  6 +++++
 test/print_settings_test.dart          | 46 ++++++++++++++++++++++++++++++++++
 3 files changed, 77 insertions(+)

## Diff
diff --git a/lib/domain/models/print_settings.dart b/lib/domain/models/print_settings.dart
new file mode 100644
index 0000000..3b0c75d
--- /dev/null
+++ b/lib/domain/models/print_settings.dart
@@ -0,0 +1,25 @@
+import 'package:equatable/equatable.dart';
+
+class PrintSettings extends Equatable {
+  /// Last known hardcoded invoice footer number. Used only when Firestore
+  /// and cache have no value so vans never print a blank supervisor line.
+  static const String fallbackSupervisorPhone = '+971 501880810';
+
+  final String supervisorPhone;
+
+  const PrintSettings({required this.supervisorPhone});
+
+  String get resolvedPhone =>
+      supervisorPhone.trim().isEmpty ? fallbackSupervisorPhone : supervisorPhone.trim();
+
+  factory PrintSettings.fromMap(Map<String, dynamic> map) {
+    return PrintSettings(
+      supervisorPhone: (map['supervisor_phone'] ?? '').toString().trim(),
+    );
+  }
+
+  Map<String, dynamic> toMap() => {'supervisor_phone': supervisorPhone};
+
+  @override
+  List<Object?> get props => [supervisorPhone];
+}
diff --git a/lib/domain/utils/supervisor_label.dart b/lib/domain/utils/supervisor_label.dart
new file mode 100644
index 0000000..64a8a95
--- /dev/null
+++ b/lib/domain/utils/supervisor_label.dart
@@ -0,0 +1,6 @@
+String formatSupervisorLine(String phone) {
+  final trimmed = phone.trim();
+  if (trimmed.isEmpty) return '';
+  if (trimmed.toLowerCase().startsWith('supervisor')) return trimmed;
+  return 'Supervisor : $trimmed';
+}
diff --git a/test/print_settings_test.dart b/test/print_settings_test.dart
new file mode 100644
index 0000000..24b701d
--- /dev/null
+++ b/test/print_settings_test.dart
@@ -0,0 +1,46 @@
+import 'package:flutter_test/flutter_test.dart';
+import 'package:van_sales/domain/models/print_settings.dart';
+import 'package:van_sales/domain/utils/supervisor_label.dart';
+
+void main() {
+  group('PrintSettings.fromMap', () {
+    test('reads supervisor_phone', () {
+      final settings = PrintSettings.fromMap({
+        'supervisor_phone': ' +971 50 111 2222 ',
+      });
+      expect(settings.supervisorPhone, '+971 50 111 2222');
+    });
+
+    test('empty or missing field yields empty phone', () {
+      expect(PrintSettings.fromMap({}).supervisorPhone, '');
+      expect(PrintSettings.fromMap({'supervisor_phone': '  '}).supervisorPhone, '');
+    });
+
+    test('resolvedPhone uses fallback when empty', () {
+      expect(
+        const PrintSettings(supervisorPhone: '').resolvedPhone,
+        PrintSettings.fallbackSupervisorPhone,
+      );
+      expect(
+        const PrintSettings(supervisorPhone: '+971 50 000 0000').resolvedPhone,
+        '+971 50 000 0000',
+      );
+    });
+  });
+
+  group('formatSupervisorLine', () {
+    test('prefixes Supervisor when the value is a phone', () {
+      expect(
+        formatSupervisorLine('+971 501880810'),
+        'Supervisor : +971 501880810',
+      );
+    });
+
+    test('does not double-prefix an already labeled line', () {
+      expect(
+        formatSupervisorLine('Supervisor : +971 501880810'),
+        'Supervisor : +971 501880810',
+      );
+    });
+  });
+}
