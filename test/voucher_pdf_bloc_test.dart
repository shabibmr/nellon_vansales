import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/print_settings.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/salesperson.dart';
import 'package:van_sales/domain/repositories/customer_repository.dart';
import 'package:van_sales/domain/repositories/print_settings_repository.dart';
import 'package:van_sales/domain/repositories/session_repository.dart';
import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';
import 'package:van_sales/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart';
import 'package:van_sales/ui/features/voucher_pdf/bloc/voucher_pdf_event.dart';
import 'package:van_sales/ui/features/voucher_pdf/bloc/voucher_pdf_state.dart';

class FakePrintSettingsRepository implements PrintSettingsRepository {
  FakePrintSettingsRepository(this._phone);

  final String _phone;

  @override
  String get supervisorPhone => _phone;

  @override
  Future<void> hydrate() async {}

  @override
  Future<PrintSettings> refresh() async =>
      PrintSettings(supervisorPhone: _phone);
}

class RecordingVoucherPdfRepository implements VoucherPdfRepository {
  String? capturedSupervisorPhone;

  @override
  Future<Uint8List> generateVoucherPdf({
    required VoucherType type,
    required dynamic voucher,
    required Organization org,
    required Customer? customer,
    Salesperson? salesperson,
    String? supervisorPhone,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    Uint8List? logoBytes,
  }) async {
    capturedSupervisorPhone = supervisorPhone;
    return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x2D]);
  }

  @override
  String getSafeFilename({required VoucherType type, required dynamic voucher}) =>
      'test_voucher.pdf';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      return '';
    }
    return Future<void>.value();
  }
}

class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository(this.org);

  final Organization? org;

  @override
  Organization? getOrganization() => org;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers;

  FakeCustomerRepository(this.customers);

  @override
  Customer? getCustomerById(String id) => customers[id];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return <dynamic>[];
    return Future<void>.value();
  }
}

void main() {
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

  final invoice = SalesInvoice(
    id: 'inv-bloc-1',
    invoiceNumber: 'INV-BLOC-001',
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

  group('VoucherPdfBloc - supervisor phone wiring', () {
    test('passes PrintSettingsRepository supervisor phone to generateVoucherPdf',
        () async {
      const firestorePhone = '+971 50 999 0000';
      final pdfRepo = RecordingVoucherPdfRepository();
      final printSettings = FakePrintSettingsRepository(firestorePhone);
      final bloc = VoucherPdfBloc(
        pdfService: pdfRepo,
        printSettings: printSettings,
        customerRepository: FakeCustomerRepository({customer.id: customer}),
        sessionRepository: FakeSessionRepository(org),
      );

      bloc.add(
        GenerateVoucherPdfPreviewRequested(
          type: VoucherType.salesInvoice,
          voucher: invoice,
        ),
      );

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<VoucherPdfLoading>(),
          isA<VoucherPdfReady>(),
        ]),
      );

      expect(pdfRepo.capturedSupervisorPhone, firestorePhone);
      await bloc.close();
    });
  });
}
