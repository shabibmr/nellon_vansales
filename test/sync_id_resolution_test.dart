import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/domain/models/sales_order.dart';
import 'package:van_sales/domain/models/item.dart';

/// Always reports "online" so [SyncWorker.syncPendingItems] proceeds past its
/// connectivity gate without touching the real platform channel.
Future<List<ConnectivityResult>> fakeCheckConnectivity() async => [
  ConnectivityResult.wifi,
];

/// In-memory stand-in for the queue + orders that [SyncWorker] reads/writes,
/// without touching real Hive boxes.
class FakeHiveDatabaseService extends HiveDatabaseService {
  final Map<String, SyncQueueItem> _queue = {};
  final Map<String, SalesOrder> _orders = {};

  @override
  List<SyncQueueItem> getSyncQueue() => _queue.values.toList();

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    _queue[item.id] = item;
  }

  @override
  Future<void> updateSyncItem(SyncQueueItem item) async {
    _queue[item.id] = item;
  }

  @override
  Future<void> dequeueSyncItem(String id) async {
    _queue.remove(id);
  }

  @override
  List<SalesOrder> getLocalOrders() => _orders.values.toList();

  @override
  Future<void> saveLocalOrder(SalesOrder order) async {
    _orders[order.id] = order;
  }
}

/// Zoho client stub returning deterministic remote IDs; the sync-type
/// argument passed through the payload determines how each fixture resolves.
class FakeZohoApiClient extends ZohoApiClient {
  FakeZohoApiClient() : super(dbService: FakeHiveDatabaseService());

  bool failNextInvoiceSync = false;
  Object failureToThrow = Exception('generic failure');
  Map<String, dynamic>? lastInvoicePayload;

  @override
  Future<String> syncCustomer(Map<String, dynamic> customerJson) async =>
      'zoho_cust_PERMANENT';

  @override
  Future<String> syncSalesOrder(Map<String, dynamic> salesOrderJson) async =>
      'zoho_so_PERMANENT';

  @override
  Future<String> syncInvoice(Map<String, dynamic> invoiceJson) async {
    lastInvoicePayload = invoiceJson;
    if (failNextInvoiceSync) throw failureToThrow;
    return 'zoho_inv_PERMANENT';
  }

  @override
  Future<String> convertSalesOrderToInvoice(
    String salesOrderId, [
    Map<String, dynamic>? body,
  ]) async => 'zoho_invoice_from_so';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testItem = Item(
    id: 'item_1',
    name: 'Widget',
    sku: 'SKU1',
    rate: 10.0,
    stock: 100,
    description: '',
    taxName: 'No Tax',
    taxPercentage: 0.0,
  );

  group('Sync ID resolution', () {
    test(
      'customer sync patches the temp customer_id on a queued invoice',
      () async {
        final db = FakeHiveDatabaseService();
        final api = FakeZohoApiClient();
        final worker = SyncWorker(
          dbService: db,
          apiClient: api,
          checkConnectivity: fakeCheckConnectivity,
        );

        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_cust_1',
            type: 'customer',
            payload: const {'contact_name': 'Acme'},
            timestamp: DateTime.now(),
          ),
        );
        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_inv_1',
            type: 'invoice',
            payload: const {'customer_id': 'temp_cust_1', 'line_items': []},
            timestamp: DateTime.now(),
          ),
        );

        await worker.syncPendingItems();

        expect(db.getSyncQueue(), isEmpty);
        // The invoice payload actually sent to Zoho must carry the
        // permanent customer id, not the temp offline id it was created with.
        expect(
          api.lastInvoicePayload?['customer_id'],
          equals('zoho_cust_PERMANENT'),
        );
      },
    );

    test(
      'sales order sync persists the permanent zohoOrderId on the local order '
      'and patches a pending convert_so item',
      () async {
        final db = FakeHiveDatabaseService();
        final api = FakeZohoApiClient();
        final worker = SyncWorker(
          dbService: db,
          apiClient: api,
          checkConnectivity: fakeCheckConnectivity,
        );

        await db.saveLocalOrder(
          SalesOrder(
            id: 'temp_so_1',
            orderNumber: 'SO-TEMP-1',
            customerId: 'cust_1',
            customerName: 'Acme',
            date: DateTime.now(),
            shipmentDate: DateTime.now(),
            items: const [
              OrderLineItem(
                item: testItem,
                quantity: 2,
                rate: 10.0,
                taxPercentage: 0,
              ),
            ],
            notes: '',
          ),
        );

        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_so_1',
            type: 'sales_order',
            payload: const {'customer_id': 'cust_1', 'line_items': []},
            timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        );
        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_convert_1',
            type: 'convert_so',
            payload: const {'salesorder_id': 'temp_so_1'},
            timestamp: DateTime.now(),
          ),
        );

        await worker.syncPendingItems();

        // _persistOrderZohoId: the local order now carries the permanent id
        // and is no longer marked pending.
        final order = db.getLocalOrders().firstWhere(
          (o) => o.id == 'temp_so_1',
        );
        expect(order.zohoOrderId, equals('zoho_so_PERMANENT'));
        expect(order.isPendingSync, isFalse);

        // _resolveTempOrderIdsInQueue: the convert_so item's salesorder_id
        // must have been swapped to the permanent id before it was synced.
        expect(
          db.getSyncQueue().any((i) => i.id == 'temp_convert_1'),
          isFalse,
        ); // synced successfully -> dequeued
      },
    );
  });

  group('Offline-queue failure handling', () {
    test(
      'a failing sync item is marked failed and tagged with its error category',
      () async {
        final db = FakeHiveDatabaseService();
        final api = FakeZohoApiClient()
          ..failNextInvoiceSync = true
          ..failureToThrow = Exception('SocketException: Failed host lookup');
        final worker = SyncWorker(
          dbService: db,
          apiClient: api,
          checkConnectivity: fakeCheckConnectivity,
        );

        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_inv_fail',
            type: 'invoice',
            payload: const {'customer_id': 'cust_1', 'line_items': []},
            timestamp: DateTime.now(),
          ),
        );

        await worker.syncPendingItems();

        final failed = db.getSyncQueue().firstWhere(
          (i) => i.id == 'temp_inv_fail',
        );
        expect(failed.status, SyncStatus.failed);
        expect(failed.errorMessage, startsWith('[Retryable]'));
        expect(failed.errorMessage, contains('SocketException'));
      },
    );

    test(
      'a permanent (validation-shaped) failure is tagged Needs Attention',
      () async {
        final db = FakeHiveDatabaseService();
        final api = FakeZohoApiClient()
          ..failNextInvoiceSync = true
          ..failureToThrow = Exception('Invalid customer_id: cannot be blank');
        final worker = SyncWorker(
          dbService: db,
          apiClient: api,
          checkConnectivity: fakeCheckConnectivity,
        );

        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_inv_invalid',
            type: 'invoice',
            payload: const {'customer_id': '', 'line_items': []},
            timestamp: DateTime.now(),
          ),
        );

        await worker.syncPendingItems();

        final failed = db.getSyncQueue().firstWhere(
          (i) => i.id == 'temp_inv_invalid',
        );
        expect(failed.status, SyncStatus.failed);
        expect(failed.errorMessage, startsWith('[Needs Attention]'));
      },
    );
  });

  group('Auto-retry backoff', () {
    test(
      'a transient-failed item is not retried before its backoff window elapses',
      () async {
        final db = FakeHiveDatabaseService();
        final api = FakeZohoApiClient();
        final worker = SyncWorker(
          dbService: db,
          apiClient: api,
          checkConnectivity: fakeCheckConnectivity,
        );

        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_inv_backoff',
            type: 'invoice',
            payload: const {'customer_id': 'cust_1', 'line_items': []},
            status: SyncStatus.failed,
            errorMessage: '[Retryable] Exception: SocketException',
            retryCount: 1,
            // retryCount 1 -> 60s backoff; only 5s have elapsed since failure.
            timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
          ),
        );

        await worker.syncPendingItems();

        // Still queued and untouched: the auto-retry path must have skipped
        // it since its backoff window (60s for retryCount 1) hasn't elapsed.
        final item = db.getSyncQueue().firstWhere(
          (i) => i.id == 'temp_inv_backoff',
        );
        expect(item.status, SyncStatus.failed);
        expect(item.retryCount, equals(1));
      },
    );

    test(
      'a transient-failed item is retried once its backoff window has elapsed',
      () async {
        final db = FakeHiveDatabaseService();
        final api = FakeZohoApiClient();
        final worker = SyncWorker(
          dbService: db,
          apiClient: api,
          checkConnectivity: fakeCheckConnectivity,
        );

        await db.enqueueSyncItem(
          SyncQueueItem(
            id: 'temp_inv_ready',
            type: 'invoice',
            payload: const {'customer_id': 'cust_1', 'line_items': []},
            status: SyncStatus.failed,
            errorMessage: '[Retryable] Exception: SocketException',
            retryCount: 0,
            // retryCount 0 -> 30s backoff; 40s have elapsed, so it's eligible.
            timestamp: DateTime.now().subtract(const Duration(seconds: 40)),
          ),
        );

        await worker.syncPendingItems();

        // Retried and succeeded (FakeZohoApiClient.syncInvoice succeeds by
        // default) -> dequeued entirely.
        expect(db.getSyncQueue().any((i) => i.id == 'temp_inv_ready'), isFalse);
      },
    );

    test('a Needs Attention item is never retried automatically but is retried '
        'with forceRetryAll', () async {
      final db = FakeHiveDatabaseService();
      final api = FakeZohoApiClient();
      final worker = SyncWorker(
        dbService: db,
        apiClient: api,
        checkConnectivity: fakeCheckConnectivity,
      );

      await db.enqueueSyncItem(
        SyncQueueItem(
          id: 'temp_inv_needs_attention',
          type: 'invoice',
          payload: const {'customer_id': 'cust_1', 'line_items': []},
          status: SyncStatus.failed,
          errorMessage: '[Needs Attention] Exception: Invalid customer_id',
          retryCount: 3,
          // Long past any backoff window, but still permanent.
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      await worker.syncPendingItems();

      expect(
        db
            .getSyncQueue()
            .firstWhere((i) => i.id == 'temp_inv_needs_attention')
            .status,
        SyncStatus.failed,
      );

      await worker.syncPendingItems(forceRetryAll: true);

      // forceRetryAll bypasses both the permanent-failure and backoff
      // checks, so this now succeeds and is dequeued.
      expect(
        db.getSyncQueue().any((i) => i.id == 'temp_inv_needs_attention'),
        isFalse,
      );
    });
  });
}
