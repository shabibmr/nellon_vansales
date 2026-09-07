import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/voucher_pdf_service.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/print_settings.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/salesperson.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';
import 'package:van_sales/domain/utils/supervisor_label.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const org = Organization(
    id: 'org1',
    name: 'Test Van Co LLC',
    currencyCode: 'AED',
    currencySymbol: 'AED',
    fiscalYearStartMonth: '4',
    timeZone: 'Asia/Dubai',
    address: '12 Warehouse Rd, Dubai, UAE',
    phone: '+971 4 123 4567',
    trn: '100123456700003',
  );

  const customer = Customer(
    id: 'c1',
    name: 'Al Noor Supermarket',
    companyName: 'Al Noor Trading LLC',
    email: 'info@alnoor.ae',
    phone: '+971 50 123 4567',
    address: 'Shop 4, Deira, Dubai',
    trn: '100987654300003',
    outstandingBalance: 500,
    creditLimit: 5000,
    routeId: 'r1',
    sequence: 1,
  );

  const salesperson = Salesperson(
    id: 'sp1',
    name: 'Rashid Khan',
    email: 'rashid@testvanco.ae',
    phone: '+971 55 987 6543',
  );

  const item = Item(
    id: 'i1',
    name: 'Premium Product',
    sku: 'SKU-001',
    rate: 100,
    stock: 200,
    description: 'Product Description',
    taxName: 'VAT 5%',
    taxPercentage: 5,
    uom: 'pcs',
  );

  group('VoucherPdfService - All Voucher Types', () {
    late VoucherPdfService service;

    setUp(() {
      service = VoucherPdfService();
    });

    test('generates valid PDF bytes for SalesInvoice with TRN & Salesman', () async {
      final invoice = SalesInvoice(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        customerId: customer.id,
        customerName: customer.name,
        date: DateTime(2026, 1, 15),
        dueDate: DateTime(2026, 1, 30),
        items: const [
          InvoiceLineItem(
            item: item,
            quantity: 2,
            rate: 100,
            taxPercentage: 5,
          ),
        ],
        notes: 'Delivery note',
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: org,
        customer: customer,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));

      final filename = service.getSafeFilename(
        type: VoucherType.salesInvoice,
        voucher: invoice,
      );
      expect(filename, 'sales_invoice_INV-001.pdf');
    });

    test('generates valid PDF bytes for SalesOrder with TRN & Salesman', () async {
      final order = SalesOrder(
        id: 'so-1',
        orderNumber: 'SO-001',
        customerId: customer.id,
        customerName: customer.name,
        date: DateTime(2026, 1, 15),
        shipmentDate: DateTime(2026, 1, 20),
        items: const [
          OrderLineItem(
            item: item,
            quantity: 5,
            rate: 100,
            taxPercentage: 5,
          ),
        ],
        notes: 'Order note',
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.salesOrder,
        voucher: order,
        org: org,
        customer: customer,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('generates valid PDF bytes for SalesReturn (Credit Note)', () async {
      final returnVoucher = SalesReturn(
        id: 'cr-1',
        creditNoteNumber: 'CN-001',
        customerId: customer.id,
        customerName: customer.name,
        date: DateTime(2026, 1, 15),
        items: const [
          SalesReturnLineItem(
            invoiceLineItem: InvoiceLineItem(
              item: item,
              quantity: 1,
              rate: 100,
              taxPercentage: 5,
            ),
            returnedQuantity: 1,
          ),
        ],
        reason: 'Damaged item',
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.salesReturn,
        voucher: returnVoucher,
        org: org,
        customer: customer,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('generates valid PDF bytes for ReceiptVoucher', () async {
      final receipt = ReceiptVoucher(
        id: 'rc-1',
        paymentNumber: 'RC-001',
        customerId: customer.id,
        customerName: customer.name,
        allocations: const [],
        amount: 500,
        paymentMode: 'cash',
        referenceNumber: 'REF-001',
        date: DateTime(2026, 1, 15),
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.paymentReceipt,
        voucher: receipt,
        org: org,
        customer: customer,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('generates valid PDF bytes for ExpenseEntry', () async {
      final expense = ExpenseEntry(
        id: 'exp-1',
        date: DateTime(2026, 1, 15),
        lines: const [
          ExpenseLineItem(
            category: 'Fuel',
            amount: 75,
            description: 'Van fuel refill',
          ),
        ],
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.expenseVoucher,
        voucher: expense,
        org: org,
        customer: null,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('generates valid PDF bytes for Issue to Van StockTransfer', () async {
      final transfer = StockTransfer(
        id: 'st-load-1',
        transferNumber: 'TO-LOAD-001',
        date: DateTime(2026, 1, 15, 9, 30),
        direction: StockTransferDirection.load,
        fromLocationId: 'WH-MAIN',
        toLocationId: 'VAN-01',
        lines: const [
          StockTransferLine(
            item: item,
            quantity: 50,
            uom: 'pcs',
          ),
        ],
        notes: 'Pre-trip stock loading',
        status: 'draft',
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.stockTransfer,
        voucher: transfer,
        org: org,
        customer: null,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));

      final filename = service.getSafeFilename(
        type: VoucherType.stockTransfer,
        voucher: transfer,
      );
      expect(filename, 'stock_transfer_TO-LOAD-001.pdf');
    });

    test('generates valid PDF bytes for Stock Unloading', () async {
      final transfer = StockTransfer(
        id: 'st-unload-1',
        transferNumber: 'TO-UNLOAD-001',
        date: DateTime(2026, 1, 15, 17, 30),
        direction: StockTransferDirection.unload,
        fromLocationId: 'VAN-01',
        toLocationId: 'WH-MAIN',
        lines: const [
          StockTransferLine(
            item: item,
            quantity: 15,
            uom: 'Box',
            conversionRate: 5,
          ),
        ],
        notes: 'End of shift return',
        status: 'transferred',
      );

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.stockTransfer,
        voucher: transfer,
        org: org,
        customer: null,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));

      final filename = service.getSafeFilename(
        type: VoucherType.stockTransfer,
        voucher: transfer,
      );
      expect(filename, 'stock_transfer_TO-UNLOAD-001.pdf');
    });

    test('generates valid PDF bytes when logoBytes is provided', () async {
      final invoice = SalesInvoice(
        id: 'inv-logo',
        invoiceNumber: 'INV-LOGO-001',
        customerId: customer.id,
        customerName: customer.name,
        date: DateTime(2026, 1, 15),
        dueDate: DateTime(2026, 1, 30),
        items: const [
          InvoiceLineItem(
            item: item,
            quantity: 1,
            rate: 50,
            taxPercentage: 5,
          ),
        ],
        notes: 'Logo test',
      );

      final dummyPng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      final bytes = await service.generateVoucherPdf(
        type: VoucherType.salesInvoice,
        voucher: invoice,
        org: org,
        customer: customer,
        salesperson: salesperson,
        logoBytes: dummyPng,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });
  });

  group('VoucherPdfService - supervisor footer', () {
    late VoucherPdfService service;

    setUp(() {
      service = VoucherPdfService();
    });

    SalesInvoice _sampleInvoice() => SalesInvoice(
      id: 'inv-supervisor',
      invoiceNumber: 'INV-SUP-001',
      customerId: customer.id,
      customerName: customer.name,
      date: DateTime(2026, 1, 15),
      dueDate: DateTime(2026, 1, 30),
      items: const [
        InvoiceLineItem(
          item: item,
          quantity: 1,
          rate: 100,
          taxPercentage: 5,
        ),
      ],
      notes: '',
    );

    test('footer uses explicit supervisor phone from Firestore', () async {
      const firestorePhone = '+971 50 999 0000';
      final bytes = await service.generateVoucherPdf(
        type: VoucherType.salesInvoice,
        voucher: _sampleInvoice(),
        org: org,
        customer: customer,
        salesperson: salesperson,
        supervisorPhone: firestorePhone,
      );

      expect(bytes, isNotEmpty);
      expect(
        formatSupervisorLine(firestorePhone),
        'Supervisor : $firestorePhone',
      );
    });

    test('footer falls back to default supervisor phone when not overridden',
        () async {
      final bytes = await service.generateVoucherPdf(
        type: VoucherType.salesInvoice,
        voucher: _sampleInvoice(),
        org: org,
        customer: customer,
        salesperson: salesperson,
      );

      expect(bytes, isNotEmpty);
      expect(
        VoucherPdfService.defaultSupervisorPhone,
        PrintSettings.fallbackSupervisorPhone,
      );
      expect(
        formatSupervisorLine(VoucherPdfService.defaultSupervisorPhone),
        'Supervisor : ${PrintSettings.fallbackSupervisorPhone}',
      );
    });
  });
}
