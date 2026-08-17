import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/repositories/expense_repository_impl.dart';
import 'package:van_sales/data/repositories/invoice_repository_impl.dart';
import 'package:van_sales/data/repositories/receipt_repository_impl.dart';
import 'package:van_sales/data/repositories/sales_return_repository_impl.dart';
import 'package:van_sales/data/repositories/stock_transfer_repository_impl.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/expense_entry.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/receipt_voucher.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/sales_return.dart';
import 'package:van_sales/domain/models/stock_transfer.dart';

class _FakeDb extends HiveDatabaseService {
  final Map<String, SyncQueueItem> queue = {};
  final List<SalesInvoice> invoices = [];

  @override
  List<SyncQueueItem> getSyncQueue() => queue.values.toList();

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    queue[item.id] = item;
  }

  @override
  List<SalesInvoice> getAllLocalInvoicesUnfiltered() => invoices;
}

class _FakeApi extends ZohoApiClient {
  _FakeApi(_FakeDb db) : super(dbService: db);
}

const _item = Item(
  id: 'item_1',
  name: 'Widget',
  sku: 'SKU1',
  rate: 10,
  stock: 100,
  description: '',
  taxName: 'VAT',
  taxPercentage: 5,
);

SalesInvoice _invoice({
  required String id,
  String? zohoInvoiceId,
}) =>
    SalesInvoice(
      id: id,
      invoiceNumber: 'SHB-INV-00001',
      customerId: 'cust_1',
      customerName: 'Acme',
      date: DateTime(2026, 8, 1),
      dueDate: DateTime(2026, 8, 8),
      items: const [
        InvoiceLineItem(
          item: _item,
          quantity: 1,
          rate: 10,
          taxPercentage: 5,
        ),
      ],
      notes: '',
      isPendingSync: zohoInvoiceId == null,
      zohoInvoiceId: zohoInvoiceId,
    );

void main() {
  late _FakeDb db;
  late InvoiceRepositoryImpl invoices;
  late ReceiptRepositoryImpl receipts;
  late SalesReturnRepositoryImpl returns;
  late ExpenseRepositoryImpl expenses;
  late StockTransferRepositoryImpl transfers;

  setUp(() {
    db = _FakeDb();
    final api = _FakeApi(db);
    invoices = InvoiceRepositoryImpl(dbService: db, apiClient: api);
    receipts = ReceiptRepositoryImpl(dbService: db, apiClient: api);
    returns = SalesReturnRepositoryImpl(dbService: db, apiClient: api);
    expenses = ExpenseRepositoryImpl(dbService: db, apiClient: api);
    transfers = StockTransferRepositoryImpl(dbService: db, apiClient: api);
  });

  test('enqueueInvoice stores a typed invoice payload from the domain model',
      () async {
    final invoice = _invoice(id: 'temp_inv_1');
    await invoices.enqueueInvoice(invoice);

    final item = db.queue['temp_inv_1']!;
    expect(item.type, 'invoice');
    expect(item.payload['invoice_number'], 'SHB-INV-00001');
    expect(item.payload['customer_id'], 'cust_1');
  });

  test(
    'enqueueReceipt rewrites allocation invoice_id to the synced Zoho id',
    () async {
      db.invoices.add(
        _invoice(id: 'temp_inv_1', zohoInvoiceId: 'zoho_inv_1'),
      );
      await receipts.enqueueReceipt(
        ReceiptVoucher(
          id: 'temp_pay_1',
          paymentNumber: 'SHB-RCT-00001',
          customerId: 'cust_1',
          customerName: 'Acme',
          allocations: const [
            PaymentAllocation(
              invoiceId: 'temp_inv_1',
              invoiceNumber: 'SHB-INV-00001',
              amountApplied: 10,
            ),
          ],
          amount: 10,
          paymentMode: 'Cash',
          referenceNumber: 'SHB-RCT-00001',
          date: DateTime(2026, 8, 1),
          isPendingSync: true,
        ),
      );

      final invoices = db.queue['temp_pay_1']!.payload['invoices'] as List;
      expect(invoices.single['invoice_id'], 'zoho_inv_1');
    },
  );

  test(
    'enqueueSalesReturn rewrites line invoice_id to the synced Zoho id',
    () async {
      db.invoices.add(
        _invoice(id: 'temp_inv_1', zohoInvoiceId: 'zoho_inv_1'),
      );
      await returns.enqueueSalesReturn(
        SalesReturn(
          id: 'temp_ret_1',
          creditNoteNumber: 'SHB-CN-00001',
          customerId: 'cust_1',
          customerName: 'Acme',
          date: DateTime(2026, 8, 1),
          items: const [
            SalesReturnLineItem(
              invoiceLineItem: InvoiceLineItem(
                item: _item,
                quantity: 1,
                rate: 10,
                taxPercentage: 5,
              ),
              returnedQuantity: 1,
              invoiceId: 'temp_inv_1',
              invoiceNumber: 'SHB-INV-00001',
            ),
          ],
          reason: 'Damaged',
          isPendingSync: true,
        ),
      );

      final lines = db.queue['temp_ret_1']!.payload['line_items'] as List;
      expect(lines.single['invoice_id'], 'zoho_inv_1');
    },
  );

  test('enqueueConvertSalesOrder prefers zohoOrderId over the local id',
      () async {
    await invoices.enqueueConvertSalesOrder(
      order: SalesOrder(
        id: 'temp_so_1',
        orderNumber: 'SHB-SO-00001',
        customerId: 'cust_1',
        customerName: 'Acme',
        date: DateTime(2026, 8, 1),
        shipmentDate: DateTime(2026, 8, 2),
        items: const [],
        notes: '',
        zohoOrderId: 'zoho_so_1',
      ),
      invoice: _invoice(id: 'temp_inv_from_so'),
    );

    final item = db.queue['temp_inv_from_so']!;
    expect(item.type, 'convert_so');
    expect(item.payload['salesorder_id'], 'zoho_so_1');
    expect(item.payload['local_invoice_id'], 'temp_inv_from_so');
    expect(item.payload['invoice'], isA<Map<dynamic, dynamic>>());
    expect(
      (item.payload['invoice'] as Map<dynamic, dynamic>)['invoice_number'],
      'SHB-INV-00001',
    );
  });

  test('enqueueExpense and enqueueStockTransfer write typed queue items',
      () async {
    await expenses.enqueueExpense(
      ExpenseEntry(
        id: 'temp_exp_1',
        date: DateTime(2026, 8, 1),
        lines: const [
          ExpenseLineItem(
            category: 'Fuel',
            amount: 20,
            description: 'Diesel',
          ),
        ],
        isPendingSync: true,
      ),
    );
    await transfers.enqueueStockTransfer(
      StockTransfer(
        id: 'temp_to_1',
        transferNumber: 'TO-TEMP-1',
        date: DateTime(2026, 8, 1),
        direction: StockTransferDirection.load,
        fromLocationId: 'wh_1',
        toLocationId: 'van_1',
        lines: const [
          StockTransferLine(item: _item, quantity: 2),
        ],
        notes: '',
        isPendingSync: true,
      ),
      isUpdate: false,
    );

    expect(db.queue['temp_exp_1']!.type, 'expense');
    expect(db.queue['temp_to_1']!.type, 'stock_transfer');
    expect(db.queue['temp_to_1']!.payload['from_location_id'], 'wh_1');
  });
}
