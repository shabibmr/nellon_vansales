import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/voucher_pdf_service.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/organization.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';
import 'package:van_sales/domain/repositories/voucher_pdf_repository.dart';

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

  group('VoucherPdfService - StockTransfer', () {
    late VoucherPdfService service;

    setUp(() {
      service = VoucherPdfService();
    });

    test('generates valid PDF bytes for Issue to Van', () async {
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
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));

      final filename = service.getSafeFilename(
        type: VoucherType.stockTransfer,
        voucher: transfer,
      );
      expect(filename, 'stock_transfer_TO-UNLOAD-001.pdf');
    });
  });
}
