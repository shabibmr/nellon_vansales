import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/esc_pos/esc_pos_ticket_builder.dart';
import 'package:van_sales/data/services/esc_pos/voucher_ticket_builder.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/thermal_paper_size.dart';
import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const org = Organization(
    id: 'org1',
    name: 'Test Van Co',
    currencyCode: 'INR',
    currencySymbol: 'AED',
    fiscalYearStartMonth: '4',
    timeZone: 'Asia/Kolkata',
  );

  const customer = Customer(
    id: 'c1',
    name: 'Acme Mart',
    companyName: 'Acme Mart LLC',
    email: 'a@test.com',
    phone: '9999999999',
    address: '12 Main St',
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

    test('invoice ticket embeds UOM next to quantity', () async {
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
      // ESC/POS payload is mostly Latin-1 text; "2kg" is the qty+unit cell.
      final asText = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(asText.contains('2kg'), isTrue);
    });

    test('builds non-empty receipt ticket', () async {
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
    });

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
