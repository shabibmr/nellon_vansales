import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/widgets/empty_state.dart';

void main() {
  group('EmptyState Widget Tests', () {
    testWidgets('Renders title and message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No Data Found',
              message: 'Try clearing your filters or refreshing.',
            ),
          ),
        ),
      );

      expect(find.text('No Data Found'), findsOneWidget);
      expect(
        find.text('Try clearing your filters or refreshing.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('Renders action widget when provided', (WidgetTester tester) async {
      var actionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.refresh,
              title: 'Empty List',
              message: 'No records available.',
              action: TextButton(
                onPressed: () {
                  actionTapped = true;
                },
                child: const Text('Refresh Now'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Refresh Now'), findsOneWidget);
      await tester.tap(find.text('Refresh Now'));
      expect(actionTapped, true);
    });
  });
}
