import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/theme/app_theme.dart';
import 'package:van_sales/ui/features/dashboard/widgets/van_action_tile.dart';

void main() {
  testWidgets('VanActionTile exposes Semantics label for primary action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VanActionTile(
            title: 'Create Invoice',
            subtitle: 'Bill a customer',
            icon: Icons.receipt_long,
            color: AppTheme.primaryIndigo,
            isDark: false,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Create Invoice'), findsOneWidget);
  });
}
