import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/core/widgets/app_logo.dart';

void main() {
  testWidgets('AppLogo exposes a semantic label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppLogo(size: 40)),
      ),
    );

    expect(find.bySemanticsLabel('Nellon Van Sales'), findsOneWidget);
  });
}
