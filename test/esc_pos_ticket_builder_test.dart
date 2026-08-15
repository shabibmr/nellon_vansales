import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/organization_model.dart';
import 'package:van_sales/data/services/esc_pos/esc_pos_ticket_builder.dart';
import 'package:van_sales/data/services/esc_pos/voucher_ticket_builder.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/thermal_paper_size.dart';
import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';

String latin1Payload(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const org = Organization(
    id: 'org1',
    name: 'Test Van Co',
    currencyCode: 'AED',
    currencySymbol: 'AED',
    fiscalYearStartMonth: '4',
    timeZone: 'Asia/Kolkata',
    address: '12 Warehouse Rd, Dubai',
    phone: '+97141234567',
    trn: '100123456700003',
  );

  const customer = Customer(
    id: 'c1',
    name: 'Acme Mart',
    companyName: 'Acme Mart LLC',
    email: 'a@test.com',
    phone: '9999999999',
    address: '12 Main St Industrial Area Dubai',
    trn: '200987654300001',
    outstandingBalance: 0,
    creditLimit: 10000,
    routeId: 'r1',
    sequence: 1,
  );

  const item = Item(
    id: 'i1',
    name: 'Premium Widget Extra Long Name For Wrap',
    sku: 'SKU-1',
    rate: 100,
    stock: 10,
    description: 'Widget',
    taxName: 'GST 5%',
    taxPercentage: 5,
    uom: 'pcs',
  );

  final invoice = SalesInvoice(
    id: 'inv1',
    invoiceNumber: 'INV-100',
    customerId: 'c1',
    customerName: 'Acme Mart',
    date: DateTime(2026, 1, 15, 10, 30),
    dueDate: DateTime(2026, 1, 30),
    items: const [
      InvoiceLineItem(
        item: item,
        quantity: 2,
        rate: 100,
        taxPercentage: 5,
        discount: 0,
      ),
    ],
    notes: 'Deliver to rear gate',
  );

  group('ThermalPaperSize', () {
    test('defaults storage key to inch4', () {
      expect(ThermalPaperSizeX.fromStorageKey(null), ThermalPaperSize.inch4);
      expect(ThermalPaperSizeX.fromStorageKey('inch2'), ThermalPaperSize.inch2);
      expect(ThermalPaperSize.inch4.columns, 64);
      expect(ThermalPaperSize.inch2.columns, 32);
    });
  });

  group('EscPosTicketBuilder helpers', () {
    test('sanitize replaces rupee and non-ascii', () {
      expect(EscPosTicketBuilder.sanitize('₹100'), 'Rs100');
      expect(EscPosTicketBuilder.sanitize('hello—world'), 'hello-world');
    });

    test('toEscPosPaperSize maps inch profiles', () {
      expect(
        EscPosTicketBuilder.toEscPosPaperSize(ThermalPaperSize.inch2).value,
        1,
      );
      expect(
        EscPosTicketBuilder.toEscPosPaperSize(ThermalPaperSize.inch4).value,
        3,
      );
    });

    test('emptyRowsForMinLength pads to 8 inches at 6 lines/inch', () {
      expect(EscPosTicketBuilder.minLengthInches, 8);
      expect(EscPosTicketBuilder.linesPerInch, 6);
      expect(EscPosTicketBuilder.minLineUnits, 48);
      expect(
        EscPosTicketBuilder.emptyRowsForMinLength(
          usedUnits: 20,
          remainingUnits: 10,
        ),
        18,
      );
      expect(
        EscPosTicketBuilder.emptyRowsForMinLength(
          usedUnits: 40,
          remainingUnits: 20,
        ),
        0,
      );
    });

    test('wrapText breaks long names without dropping content', () {
      final lines = EscPosTicketBuilder.wrapText(
        'Premium Widget Extra Long Name For Wrap',
        12,
      );
      expect(lines, isNotEmpty);
      expect(lines.every((l) => l.length <= 12), isTrue);
      expect(lines.join(' '), contains('Premium'));
      expect(lines.join(' '), contains('Wrap'));
    });
  });

  group('VoucherTicketBuilder', () {
    test('builds non-empty invoice ticket for 4 inch and 2 inch', () async {
      for (final size in ThermalPaperSize.values) {
        final bytes = await VoucherTicketBuilder.build(
          type: VoucherType.salesInvoice,
          voucher: invoice,
          org: org,
          customer: customer,
          paperSize: size,
          salespersonName: 'Ravi',
        );
        expect(bytes, isNotEmpty, reason: 'size $size');
        expect(bytes.length, greaterThan(50), reason: 'size $size');
      }
    });

    test('invoice header layout and table formatting', () async {
      final bytes = await VoucherTicketBuilder.build(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: org,
        customer: customer,
        paperSize: ThermalPaperSize.inch4,
      );
      final text = latin1Payload(bytes);

      expect(text.contains('SALES INVOICE'), isTrue);
      expect(text.contains('Type:'), isFalse);
      expect(text.contains('Due:'), isFalse);
      expect(text.contains('Date: 15-01-2026'), isTrue);
      expect(text.contains('12 Warehouse Rd'), isTrue);
      expect(text.contains('Phone: +97141234567'), isTrue);
      expect(text.contains('TRN: 100123456700003'), isTrue);
      expect(text.contains('TRN: 200987654300001'), isTrue);
      expect(text.contains('Address:'), isTrue);
      expect(text.contains('|'), isTrue);
      expect(text.contains('Sl'), isTrue);
      expect(text.contains('2 pcs') || text.contains('2pcs'), isTrue);
      // Prefer spaced qty+uom
      expect(text.contains('2 pcs'), isTrue);
      expect(text.contains('AED '), isTrue);
      expect(text.contains('VAT @ 5%'), isTrue);
      expect(text.contains('Tax'), isFalse);
      expect(text.contains('In words:'), isTrue);
      expect(text.contains('AED'), isTrue);
      // Full long name should appear across payload (wrap, not hard drop)
      expect(text.contains('Premium'), isTrue);
      expect(text.contains('Wrap') || text.contains('Widget'), isTrue);
      // Section rules must be present as hyphen / equals runs (not dropped).
      expect(text.contains(List.filled(64, '-').join()), isTrue);
      expect(text.contains(List.filled(64, '=').join()), isTrue);
    });

    test('invoice ticket embeds UOM with space next to quantity', () async {
      final multiUomInvoice = SalesInvoice(
        id: 'inv2',
        invoiceNumber: 'INV-200',
        customerId: 'c1',
        customerName: 'Acme Mart',
        date: DateTime(2026, 1, 15),
        dueDate: DateTime(2026, 1, 30),
        items: const [
          InvoiceLineItem(
            item: item,
            quantity: 2,
            rate: 100,
            taxPercentage: 5,
            uom: 'kg',
            unitConversionId: '',
          ),
        ],
        notes: '',
      );
      final bytes = await VoucherTicketBuilder.build(
        type: VoucherType.salesInvoice,
        voucher: multiUomInvoice,
        org: org,
        customer: customer,
        paperSize: ThermalPaperSize.inch4,
      );
      final asText = latin1Payload(bytes);
      expect(asText.contains('2 kg'), isTrue);
      // Amount column should not glue AED into the cell for line items.
      // Totals still use "AED " with a space.
      expect(asText.contains('AED '), isTrue);
    });

    test('builds non-empty receipt ticket with amount in words', () async {
      final receipt = ReceiptVoucher(
        id: 'rc1',
        paymentNumber: 'RCP-1',
        customerId: 'c1',
        customerName: 'Acme Mart',
        allocations: const [
          PaymentAllocation(
            invoiceId: 'inv1',
            invoiceNumber: 'INV-100',
            amountApplied: 50,
          ),
        ],
        amount: 100,
        paymentMode: 'Cash',
        referenceNumber: '',
        date: DateTime(2026, 1, 15),
      );

      final bytes = await VoucherTicketBuilder.build(
        type: VoucherType.paymentReceipt,
        voucher: receipt,
        org: org,
        customer: customer,
        paperSize: ThermalPaperSize.inch4,
      );
      expect(bytes, isNotEmpty);
      final text = latin1Payload(bytes);
      expect(text.contains('RECEIPT'), isTrue);
      expect(text.contains('In words:'), isTrue);
      expect(text.contains('AED 100.00') || text.contains('AED 50.00'), isTrue);
    });

    test('prints org and customer TRN lines from live-shaped data', () async {
      final liveOrg = OrganizationModel.fromJson({
        'organization_id': '783019958',
        'name': 'KOYSON GENERAL TRADING LLC',
        'currency_code': 'AED',
        'currency_symbol': 'AED',
        'fiscal_year_start_month': 'january',
        'time_zone': 'Asia/Dubai',
        'phone': '00971545829444',
        'address': {
          'street_address1': 'JEBEL ALI IND-1, DUBAI, UAE',
          'city': 'DUBAI',
          'state': 'Dubai',
          'country': 'U.A.E',
        },
        'tax_settings': {'tax_reg_no': '100577492000003'},
      });
      const registered = Customer(
        id: 'c2',
        name: 'AL AMANAH SPICES TR FLOUR MILL',
        companyName: 'AL AMANAH SPICES TR FLOUR MILL',
        email: '',
        phone: '065260032',
        address: 'NEAR FIRE STATION ROAD MUWAILAH',
        trn: '100533986400003',
        outstandingBalance: 0,
        creditLimit: 0,
        routeId: 'r1',
        sequence: 1,
      );
      final bytes = await VoucherTicketBuilder.build(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: liveOrg,
        customer: registered,
        paperSize: ThermalPaperSize.inch4,
      );
      final text = latin1Payload(bytes);
      expect(text.contains('JEBEL ALI IND-1, DUBAI, UAE'), isTrue);
      expect(text.contains('street_address1'), isFalse);
      expect(text.contains('TRN: 100577492000003'), isTrue);
      expect(text.contains('TRN: 100533986400003'), isTrue);
    });

    test(
      'prints empty customer Phone and TRN labels when values are missing',
      () async {
        const unregistered = Customer(
          id: 'c3',
          name: 'AQSA AL MADEENA HYPERMARKET',
          companyName: 'AQSA AL MADEENA HYPERMARKET',
          email: '',
          phone: '',
          address: '',
          outstandingBalance: 0,
          creditLimit: 0,
          routeId: 'r1',
          sequence: 1,
        );
        final preview = await VoucherTicketBuilder.buildPreview(
          type: VoucherType.salesInvoice,
          voucher: invoice,
          org: org,
          customer: unregistered,
          paperSize: ThermalPaperSize.inch4,
        );
        expect(preview.plainText.contains('TRN: 100123456700003'), isTrue);
        expect(preview.plainText.contains('TRN: 200987654300001'), isFalse);
        expect(preview.lines.any((l) => l.text.trim() == 'Phone:'), isTrue);
        expect(preview.lines.any((l) => l.text.trim() == 'TRN:'), isTrue);
      },
    );

    test('prints salesperson phone at the bottom of the ticket', () async {
      final preview = await VoucherTicketBuilder.buildPreview(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: org,
        customer: customer,
        paperSize: ThermalPaperSize.inch4,
        salespersonName: 'Shinad',
        salespersonPhone: '+971565124529',
      );
      expect(
        preview.plainText.contains('Shinad ( Salesman ) : +971565124529'),
        isTrue,
      );
      expect(
        preview.plainText.contains('Suneer (Supervisor) : +971501880810'),
        isTrue,
      );
      final texts = preview.lines.map((l) => l.text).toList();
      final salesIdx = texts.indexWhere(
        (t) => t.contains('Shinad ( Salesman ) : +971565124529'),
      );
      final supervisorIdx = texts.indexWhere(
        (t) => t.contains('Suneer (Supervisor) : +971501880810'),
      );
      final thanksIdx = texts.indexWhere((t) => t.contains('Thank you'));
      expect(salesIdx, greaterThan(-1));
      expect(supervisorIdx, greaterThan(salesIdx));
      expect(thanksIdx, greaterThan(supervisorIdx));
    });

    test('prints salesman role line when number is missing', () async {
      final preview = await VoucherTicketBuilder.buildPreview(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: org,
        customer: customer,
        paperSize: ThermalPaperSize.inch4,
        salespersonName: 'Shinad',
      );
      final texts = preview.lines.map((l) => l.text).toList();
      final salesIdx = texts.indexWhere(
        (t) => t.trim() == 'Shinad ( Salesman ) :',
      );
      expect(salesIdx, greaterThan(-1));
      expect(texts[salesIdx + 1].trim(), 'Suneer (Supervisor) : +971501880810');
    });

    test('short invoice pads item table to minimum 8 inch length', () async {
      final bytes = await VoucherTicketBuilder.build(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: org,
        customer: customer,
        paperSize: ThermalPaperSize.inch4,
      );
      final text = latin1Payload(bytes);
      final emptyTableRow = RegExp(r'\| {3}\| {2,}\| {7}\| {10}\|');
      final emptyRows = emptyTableRow.allMatches(text).length;
      expect(emptyRows, greaterThanOrEqualTo(5));
      expect(text.contains('SALES INVOICE'), isTrue);
      expect(text.contains('TOTAL'), isTrue);
      expect(text.indexOf('TOTAL'), greaterThan(text.indexOf('|')));
    });

    test(
      'buildPreview matches invoice ticket content and paper columns',
      () async {
        for (final size in ThermalPaperSize.values) {
          final preview = await VoucherTicketBuilder.buildPreview(
            type: VoucherType.salesInvoice,
            voucher: invoice,
            org: org,
            customer: customer,
            paperSize: size,
            salespersonName: 'Ravi',
            salespersonPhone: '0509998887',
          );
          expect(preview.paperSize, size);
          expect(preview.lines, isNotEmpty);
          expect(preview.plainText.contains('SALES INVOICE'), isTrue);
          expect(preview.plainText.contains('Acme Mart'), isTrue);
          expect(preview.plainText.contains('Date: 15-01-2026'), isTrue);
          expect(preview.plainText.contains('In words:'), isTrue);
          expect(preview.plainText.contains('Thank you'), isTrue);
          expect(
            preview.plainText.contains('Ravi ( Salesman ) : 0509998887'),
            isTrue,
          );
          expect(preview.plainText.contains('Suneer (Supervisor)'), isTrue);
          expect(
            preview.lines.any(
              (l) => l.text == List.filled(size.columns, '=').join(),
            ),
            isTrue,
            reason: 'full-width divider for $size',
          );
          expect(
            preview.lines.any(
              (l) => l.center && l.bold && l.text == 'SALES INVOICE',
            ),
            isTrue,
          );
          expect(
            preview.lines.any(
              (l) => l.widthMultiplier == 2 && l.heightMultiplier == 2,
            ),
            isTrue,
          );
        }
      },
    );

    test(
      'buildPreview and build share the same printable invoice text',
      () async {
        final bytes = await VoucherTicketBuilder.build(
          type: VoucherType.salesInvoice,
          voucher: invoice,
          org: org,
          customer: customer,
          paperSize: ThermalPaperSize.inch4,
        );
        final preview = await VoucherTicketBuilder.buildPreview(
          type: VoucherType.salesInvoice,
          voucher: invoice,
          org: org,
          customer: customer,
          paperSize: ThermalPaperSize.inch4,
        );
        final printed = latin1Payload(bytes);
        for (final line in preview.lines) {
          final body = line.text.replaceAll(RegExp(r'\s+'), '');
          if (body.isEmpty) continue;
          expect(
            printed.replaceAll(RegExp(r'\s+'), ''),
            contains(body),
            reason: 'preview line missing from ESC/POS payload: "${line.text}"',
          );
        }
      },
    );

    test('builds non-empty test page for both sizes', () async {
      for (final size in ThermalPaperSize.values) {
        final bytes = await VoucherTicketBuilder.buildTestPage(
          paperSize: size,
          printerName: 'NC-MTP500',
        );
        expect(bytes, isNotEmpty, reason: 'size $size');
      }
    });
  });
}
