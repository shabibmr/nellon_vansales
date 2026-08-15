import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/thermal_paper_size.dart';
import 'package:van_sales/domain/models/thermal_ticket_preview.dart';
import 'package:van_sales/ui/features/thermal_print/widgets/thermal_print_preview_dialog.dart';

void main() {
  const preview = ThermalTicketPreview(
    paperSize: ThermalPaperSize.inch4,
    lines: [
      ThermalPreviewLine(text: 'TEST VAN CO', center: true, bold: true),
      ThermalPreviewLine(text: 'SALES INVOICE', center: true, bold: true),
      ThermalPreviewLine(text: 'No: INV-100          Date: 15-01-2026'),
      ThermalPreviewLine(text: 'TOTAL AED 210.00', bold: true),
    ],
  );

  Future<void> pumpDialog(WidgetTester tester, {VoidCallback? onPrint}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ThermalPrintPreviewDialog.show(
                context,
                preview: preview,
                onPrint: onPrint,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders ticket lines and paper size caption', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Thermal preview'), findsOneWidget);
    expect(find.text('Expected output on 4 inches paper'), findsOneWidget);
    expect(find.text('SALES INVOICE'), findsOneWidget);
    expect(find.text('TOTAL AED 210.00'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await pumpDialog(tester);
    expect(find.byType(ThermalPrintPreviewDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(ThermalPrintPreviewDialog), findsNothing);
  });

  testWidgets('Print pops the dialog and invokes the callback', (tester) async {
    var printed = false;
    await pumpDialog(tester, onPrint: () => printed = true);

    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printed, isTrue);
    expect(find.byType(ThermalPrintPreviewDialog), findsNothing);
  });
}
