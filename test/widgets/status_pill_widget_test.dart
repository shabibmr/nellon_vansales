import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/widgets/status_pill.dart';
import 'package:van_sales/ui/core/theme/app_theme.dart';

void main() {
  group('StatusPill Widget Tests', () {
    testWidgets('Renders label and icon correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusPill(
              label: 'Approved',
              color: AppTheme.successEmerald,
              icon: Icons.check_circle_outline,
            ),
          ),
        ),
      );

      expect(find.text('Approved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('Renders status pill without icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusPill(
              label: 'Pending',
              color: AppTheme.warningAmber,
            ),
          ),
        ),
      );

      expect(find.text('Pending'), findsOneWidget);
    });
  });
}
