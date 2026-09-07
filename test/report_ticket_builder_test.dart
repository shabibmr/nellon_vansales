import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/esc_pos/report_ticket_builder.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/thermal_paper_size.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReportTicketBuilder - 4" and 2" Thermal Printing', () {
    const org = Organization(
      id: 'org-1',
      name: 'Nellon Van Sales LLC',
      currencyCode: 'AED',
      currencySymbol: 'AED',
      fiscalYearStartMonth: '1',
      timeZone: 'Asia/Dubai',
      address: '12 Warehouse Rd, Dubai, UAE',
      phone: '+971 4 123 4567',
      trn: '100123456700003',
    );

    final headers = ['Item', 'SKU', 'Qty', 'Amount', 'Customers'];
    final rows = [
      ['Premium Product 100ml', 'SKU-001', '50 pcs', '5,000.00', '12'],
      ['Organic Coffee Blend - 250g', 'SKU-002', '20 Box', '3,200.00', '8'],
      ['Fresh Farm Dairy Milk 1L', 'SKU-003', '15 Ctn', '1,500.00', '5'],
    ];

    test('generates valid 4" (64-column) preview without TRN or SKU, and timestamp at bottom', () async {
      final generatedTime = DateTime(2026, 8, 20, 8, 30);
      final preview = await ReportTicketBuilder.buildPreview(
        title: 'Item Sales Report',
        headers: headers,
        rows: rows,
        org: org,
        paperSize: ThermalPaperSize.inch4,
        dateRangeText: '01-Aug-2026 to 20-Aug-2026',
        summaryStats: {
          'Total Items': '3',
          'Total Amount': 'AED 9,700.00',
        },
        salespersonName: 'Rashid Khan',
        salespersonPhone: '+971 55 987 6543',
        generatedAt: generatedTime,
      );

      expect(preview.paperSize, ThermalPaperSize.inch4);
      expect(preview.lines, isNotEmpty);

      final allText = preview.lines.map((l) => l.text).join('\n');

      // 1. Organization info printed, but TRN must NOT be in report header
      expect(allText, contains('NELLON VAN SALES LLC'));
      expect(allText, contains('+971 4 123 4567'));
      expect(allText, isNot(contains('100123456700003')));
      expect(allText, isNot(contains('TRN:')));

      // 2. Title & Date range
      expect(allText, contains('ITEM SALES REPORT'));
      expect(allText, contains('Period: 01-Aug-2026 to 20-Aug-2026'));

      // 3. Summary stats
      expect(allText, contains('SUMMARY:'));
      expect(allText, contains('Total Items'));
      expect(allText, contains('Total Amount'));

      // 4. SKU column must NOT be present in table header or rows
      expect(allText, isNot(contains('|SKU|')));
      expect(allText, isNot(contains('SKU-001')));
      expect(allText, isNot(contains('SKU-002')));
      expect(allText, contains('Premium Product 100ml'));

      // 5. Generated timestamp at bottom in footer
      expect(allText, contains('Generated: 20-Aug-2026 08:30 AM'));
      expect(allText, contains('Rashid Khan ( Salesman ) : +971 55 987 6543'));
      expect(allText, contains('Supervisor : +971 501880810'));
      expect(allText, contains('Thank you'));
    });

    test('generates valid 4" ESC/POS binary command bytes', () async {
      final bytes = await ReportTicketBuilder.build(
        title: 'Item Sales Report',
        headers: headers,
        rows: rows,
        org: org,
        paperSize: ThermalPaperSize.inch4,
        dateRangeText: '01-Aug-2026 to 20-Aug-2026',
        salespersonName: 'Rashid Khan',
        salespersonPhone: '+971 55 987 6543',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(200));
    });

    test('generates valid 2" (32-column) layout for smaller rolls', () async {
      final preview = await ReportTicketBuilder.buildPreview(
        title: 'Stock Report',
        headers: ['Item', 'Rate', 'Stock'],
        rows: [
          ['Item 1', '10.00', '100'],
          ['Item 2', '25.50', '40'],
        ],
        org: org,
        paperSize: ThermalPaperSize.inch2,
      );

      expect(preview.paperSize, ThermalPaperSize.inch2);
      expect(preview.lines, isNotEmpty);
      final allText = preview.lines.map((l) => l.text).join('\n');
      expect(allText, contains('STOCK REPORT'));
      expect(allText, contains('Generated:'));
      expect(allText, isNot(contains('TRN:')));
    });
  });
}
