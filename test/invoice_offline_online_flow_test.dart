import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sales_invoice_model.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/submit_result.dart';

import 'sync_id_resolution_test.dart';

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

  test(
    'offline invoice enqueue then online drain persists the Zoho id',
    () async {
      var online = false;
      Future<List<ConnectivityResult>> check() async => [
        online ? ConnectivityResult.wifi : ConnectivityResult.none,
      ];

      final db = FakeHiveDatabaseService();
      await db.saveItems([_item]);
      final worker = SyncWorker(
        dbService: db,
        apiClient: FakeZohoApiClient(),
        checkConnectivity: check,
      );

      final queued = await worker.submitOrEnqueue(
        SyncQueueItem(
          id: 'temp_inv_new',
          type: 'invoice',
          payload: SalesInvoiceModel.fromDomain(_invoice()).toJson(),
          timestamp: DateTime.now(),
        ),
      );

      expect(queued, SubmitResult.queued);
      expect(db.getSyncQueue(), hasLength(1));
      expect(db.getAllLocalInvoicesUnfiltered(), isEmpty);

      online = true;
      await worker.syncPendingItems();

      expect(db.getSyncQueue(), isEmpty);
      final saved = db.getAllLocalInvoicesUnfiltered().single;
      expect(saved.zohoInvoiceId, 'zoho_inv_PERMANENT');
      expect(saved.isPendingSync, isFalse);
    },
  );
}
