import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sales_invoice_model.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/models/customer.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/submit_result.dart';
import 'package:van_sales/domain/utils/stock_rules.dart';

import 'sync_id_resolution_test.dart';

Future<List<ConnectivityResult>> _offline() async => [ConnectivityResult.none];

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

SalesInvoice _invoice() => SalesInvoice(
  id: 'temp_inv_new',
  invoiceNumber: 'SHB-INV-00010',
  customerId: 'cust_1',
  customerName: 'Acme',
  date: DateTime(2026, 8, 1),
  dueDate: DateTime(2026, 8, 8),
  items: const [
    InvoiceLineItem(item: _item, quantity: 2, rate: 10, taxPercentage: 5),
  ],
  notes: '',
  isPendingSync: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SyncQueueItem invoiceItem() => SyncQueueItem(
    id: 'temp_inv_new',
    type: 'invoice',
    payload: SalesInvoiceModel.fromDomain(_invoice()).toJson(),
    timestamp: DateTime.now(),
  );

  group('submitOrEnqueue', () {
    test('offline queues only — history and stock unchanged', () async {
      final db = FakeHiveDatabaseService();
      await db.saveItems([_item]);
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: _offline,
      );

      final result = await worker.submitOrEnqueue(invoiceItem());

      expect(result, SubmitResult.queued);
      expect(db.getSyncQueue().single.id, 'temp_inv_new');
      expect(db.getAllLocalInvoicesUnfiltered(), isEmpty);
      expect(db.getItems().single.stock, 100);
    });

    test('programming Error is not queued as a sync failure', () async {
      final db = FakeHiveDatabaseService();
      final api = FakeZohoApiClient()
        ..failNextInvoiceSync = true
        ..failureToThrow = ArgumentError('bug');
      final worker = SyncWorker(
        dbService: db,
        apiClient: api,
        checkConnectivity: fakeCheckConnectivity,
      );

      await expectLater(
        worker.submitOrEnqueue(invoiceItem()),
        throwsA(isA<ArgumentError>()),
      );
      expect(db.getSyncQueue(), isEmpty);
    });

    test('Zoho failure queues only — history empty', () async {
      final db = FakeHiveDatabaseService();
      final api = FakeZohoApiClient()
        ..failNextInvoiceSync = true
        ..failureToThrow = Exception('SocketException: Failed host lookup');
      final worker = SyncWorker(
        dbService: db,
        apiClient: api,
        checkConnectivity: fakeCheckConnectivity,
      );

      final result = await worker.submitOrEnqueue(invoiceItem());

      expect(result, SubmitResult.queued);
      final queued = db.getSyncQueue().single;
      expect(queued.status, SyncStatus.failed);
      expect(queued.errorMessage, startsWith('[Retryable]'));
      expect(queued.retryCount, 0);
      expect(db.getAllLocalInvoicesUnfiltered(), isEmpty);
    });

    test('Zoho success persists invoice with zoho id and does not queue', () async {
      final db = FakeHiveDatabaseService();
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: fakeCheckConnectivity,
      );

      final result = await worker.submitOrEnqueue(invoiceItem());

      expect(result, SubmitResult.synced);
      expect(db.getSyncQueue(), isEmpty);
      final saved = db.getAllLocalInvoicesUnfiltered().single;
      expect(saved.zohoInvoiceId, 'zoho_inv_PERMANENT');
      expect(saved.isPendingSync, isFalse);
      expect(saved.invoiceNumber, 'SHB-INV-00010');
    });

    test('customer success inserts master with Zoho contact id', () async {
      final db = FakeHiveDatabaseService();
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: fakeCheckConnectivity,
      );

      final result = await worker.submitOrEnqueue(
        SyncQueueItem(
          id: 'temp_cust_1',
          type: 'customer',
          payload: const {
            'contact_name': 'Acme',
            'company_name': 'Acme Co',
            'phone': '050',
          },
          timestamp: DateTime.now(),
        ),
      );

      expect(result, SubmitResult.synced);
      expect(db.getCustomers().single.id, 'zoho_cust_PERMANENT');
      expect(db.getCustomers().single.name, 'Acme');
      expect(db.getCustomers().single.isPendingSync, isFalse);
    });

    test('GPS success writes master only after API ok', () async {
      final db = FakeHiveDatabaseService();
      await db.insertCustomer(
        const Customer(
          id: 'cust_1',
          name: 'Acme',
          companyName: '',
          email: '',
          phone: '',
          address: '',
          outstandingBalance: 0,
          creditLimit: 0,
          routeId: 'r1',
          sequence: 1,
        ),
      );
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: fakeCheckConnectivity,
      );

      final result = await worker.submitOrEnqueue(
        SyncQueueItem(
          id: 'gps_1',
          type: 'customer_gps_update',
          payload: const {
            'contact_id': 'cust_1',
            'latitude': 25.2,
            'longitude': 55.3,
          },
          timestamp: DateTime.now(),
        ),
      );

      expect(result, SubmitResult.synced);
      expect(db.getCustomers().single.latitude, 25.2);
      expect(db.getCustomers().single.longitude, 55.3);
    });

    test('convert_so success inserts invoice and marks order invoiced', () async {
      final db = FakeHiveDatabaseService();
      await db.saveLocalOrder(
        SalesOrder(
          id: 'so_1',
          orderNumber: 'SHB-SO-00001',
          customerId: 'cust_1',
          customerName: 'Acme',
          date: DateTime(2026, 8, 1),
          shipmentDate: DateTime(2026, 8, 2),
          items: const [
            OrderLineItem(item: _item, quantity: 1, rate: 10, taxPercentage: 0),
          ],
          notes: '',
          zohoOrderId: 'zoho_so_PERMANENT',
        ),
      );
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: fakeCheckConnectivity,
      );

      final invoice = _invoice();
      final result = await worker.submitOrEnqueue(
        SyncQueueItem(
          id: invoice.id,
          type: 'convert_so',
          payload: {
            'salesorder_id': 'zoho_so_PERMANENT',
            'source_order_id': 'so_1',
            'local_invoice_id': invoice.id,
            'invoice': SalesInvoiceModel.fromDomain(invoice).toJson(),
          },
          timestamp: DateTime.now(),
        ),
      );

      expect(result, SubmitResult.synced);
      expect(db.getAllLocalInvoicesUnfiltered().single.zohoInvoiceId,
          'zoho_invoice_from_so');
      expect(db.getLocalOrders().single.status, SalesOrderStatus.invoiced);
    });

    test('insufficient stock throws and does not queue', () async {
      final db = FakeHiveDatabaseService();
      await db.saveItems([_item.copyWith(stock: 1)]);
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: fakeCheckConnectivity,
      );

      expect(
        () => worker.submitOrEnqueue(invoiceItem()),
        throwsA(isA<InsufficientStockException>()),
      );
      expect(db.getSyncQueue(), isEmpty);
      expect(db.getAllLocalInvoicesUnfiltered(), isEmpty);
    });
  });
}
