import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/domain/models/item.dart';
import 'package:van_sales/domain/models/sales_invoice.dart';
import 'package:van_sales/domain/models/sales_order.dart';

/// Regression coverage for the race between an editor save (which enqueues a
/// background sync push) and an immediate list reload firing right after —
/// both eventually call into [HiveDatabaseService.saveRemoteOrders], which
/// used to treat "id present in the fresh remote fetch" as proof a pending
/// local edit had already landed in Zoho, even though an update never
/// changes the order's id, so this was true from the very first premature
/// reload. `mergeRemoteOrders` is the pure merge step behind that method —
/// tested directly here without a real Hive box.
void main() {
  const item = Item(
    id: 'item_1',
    name: 'Widget',
    sku: 'SKU1',
    rate: 10,
    stock: 0,
    description: '',
    taxName: 'VAT',
    taxPercentage: 5,
    uom: 'pcs',
  );

  OrderLineItem line(double qty) =>
      OrderLineItem(item: item, quantity: qty, rate: 10, taxPercentage: 5);

  SalesOrder order({
    required String id,
    required List<OrderLineItem> items,
    bool isPendingSync = false,
    String? zohoOrderId,
    String notes = '',
  }) => SalesOrder(
    id: id,
    orderNumber: 'SO-00001',
    customerId: 'cust_1',
    customerName: 'Acme',
    date: DateTime(2026, 7, 1),
    shipmentDate: DateTime(2026, 7, 5),
    items: items,
    notes: notes,
    isPendingSync: isPendingSync,
    zohoOrderId: zohoOrderId,
  );

  test(
    'a pending edit whose sync item is still queued survives a stale remote fetch',
    () {
      // The user just edited so_9001 (now 2 lines) and saved; the background
      // sync push for it hasn't landed in Zoho yet, so the list reload that
      // fires right after still sees the old (1-line) remote copy under the
      // same id — updates never change the id.
      final current = [
        order(
          id: 'so_9001',
          items: [line(1), line(2)],
          isPendingSync: true,
          zohoOrderId: 'so_9001',
        ),
      ];
      final remote = [
        order(id: 'so_9001', items: const [], zohoOrderId: 'so_9001'),
      ];

      final merged = HiveDatabaseService.mergeRemoteOrders(
        current: current,
        remote: remote,
        queuedOrderIds: {'so_9001'}, // update_sales_order still in the queue
      );

      final result = merged.singleWhere((o) => o.id == 'so_9001');
      expect(result.isPendingSync, isTrue);
      expect(result.items, hasLength(2));
    },
  );

  test(
    'once the queue item for it is gone, remote is treated as authoritative',
    () {
      final current = [
        order(
          id: 'so_9001',
          items: [line(1), line(2)],
          isPendingSync: true,
          zohoOrderId: 'so_9001',
        ),
      ];
      // Zoho now reflects the edit (header-only, as the list endpoint omits
      // line_items) and the queue item has been dequeued by SyncWorker.
      final remote = [
        order(id: 'so_9001', items: const [], zohoOrderId: 'so_9001'),
      ];

      final merged = HiveDatabaseService.mergeRemoteOrders(
        current: current,
        remote: remote,
        queuedOrderIds: const {},
      );

      final result = merged.singleWhere((o) => o.id == 'so_9001');
      // Header-only remote still borrows the locally-cached line items.
      expect(result.items, hasLength(2));
      expect(result.isPendingSync, isFalse);
    },
  );

  test('a local order outside the fetched (date-scoped) range survives untouched', () {
    final current = [
      order(id: 'so_old', items: [line(1)], zohoOrderId: 'so_old'),
    ];
    final remote = <SalesOrder>[]; // e.g. a today-only fetch

    final merged = HiveDatabaseService.mergeRemoteOrders(
      current: current,
      remote: remote,
      queuedOrderIds: const {},
      pruneMissingInRange: true,
      rangeStart: DateTime(2026, 8, 5),
      rangeEnd: DateTime(2026, 8, 5),
    );

    expect(merged, hasLength(1));
    expect(merged.single.id, 'so_old');
  });

  test(
    'a synced local order inside the fetched range missing from remote is pruned',
    () {
      // User refreshed an older window that used to include so_deleted; Zoho
      // no longer returns it (deleted remotely). Hive must drop the stale row.
      // Factory default date is 2026-07-01 (inside the window below).
      final inRange = order(
        id: 'so_deleted',
        items: [line(1)],
        zohoOrderId: 'so_deleted',
      );
      final outOfRange = SalesOrder(
        id: 'so_other_day',
        orderNumber: 'SO-00002',
        customerId: 'cust_1',
        customerName: 'Acme',
        date: DateTime(2026, 6, 1),
        shipmentDate: DateTime(2026, 6, 5),
        items: [line(1)],
        notes: '',
        zohoOrderId: 'so_other_day',
      );

      final merged = HiveDatabaseService.mergeRemoteOrders(
        current: [inRange, outOfRange],
        remote: const [],
        queuedOrderIds: const {},
        pruneMissingInRange: true,
        rangeStart: DateTime(2026, 7, 1),
        rangeEnd: DateTime(2026, 7, 31),
      );

      expect(merged.map((o) => o.id), ['so_other_day']);
    },
  );

  test(
    'single-order upsert without prune leaves other local orders intact',
    () {
      final current = [
        order(id: 'so_a', items: [line(1)], zohoOrderId: 'so_a'),
        order(id: 'so_b', items: [line(1)], zohoOrderId: 'so_b'),
      ];
      final remote = [
        order(id: 'so_a', items: const [], zohoOrderId: 'so_a'),
      ];

      final merged = HiveDatabaseService.mergeRemoteOrders(
        current: current,
        remote: remote,
        queuedOrderIds: const {},
        // detail fetch: pruneMissingInRange defaults false
      );

      expect(merged.map((o) => o.id).toSet(), {'so_a', 'so_b'});
    },
  );

  test(
    'pending queued edit inside the prune window is never dropped',
    () {
      final current = [
        order(
          id: 'so_9001',
          items: [line(2)],
          isPendingSync: true,
          zohoOrderId: 'so_9001',
        ),
      ];

      final merged = HiveDatabaseService.mergeRemoteOrders(
        current: current,
        remote: const [],
        queuedOrderIds: {'so_9001'},
        pruneMissingInRange: true,
        rangeStart: DateTime(2026, 7, 1),
        rangeEnd: DateTime(2026, 7, 31),
      );

      expect(merged.single.id, 'so_9001');
      expect(merged.single.isPendingSync, isTrue);
    },
  );

  test('a still-unsynced create (no zohoOrderId yet) is never dropped by a list refresh', () {
    final current = [
      order(id: 'temp_so_1', items: [line(1)], isPendingSync: true),
    ];
    final remote = [
      order(id: 'so_other', items: const [], zohoOrderId: 'so_other'),
    ];

    final merged = HiveDatabaseService.mergeRemoteOrders(
      current: current,
      remote: remote,
      queuedOrderIds: const {'temp_so_1'},
    );

    expect(merged.map((o) => o.id), containsAll(['temp_so_1', 'so_other']));
  });

  test('remote van stamp wins over stale local HQ locationId', () {
    final current = [
      SalesOrder(
        id: 'so_1',
        orderNumber: 'SO-1',
        customerId: 'c1',
        customerName: 'Acme',
        date: DateTime(2026, 8, 5),
        shipmentDate: DateTime(2026, 8, 6),
        items: [line(1)],
        notes: '',
        zohoOrderId: 'so_1',
        // Bad: previously parsed Zoho primary branch as locationId.
        locationId: 'hq_primary_branch',
      ),
    ];
    final remote = [
      SalesOrder(
        id: 'so_1',
        orderNumber: 'SO-1',
        customerId: 'c1',
        customerName: 'Acme',
        date: DateTime(2026, 8, 5),
        shipmentDate: DateTime(2026, 8, 6),
        items: const [],
        notes: '',
        zohoOrderId: 'so_1',
        listedTotal: 170,
        // Session van stamp from fetchRemoteOrders.
        locationId: 'van_wh_7',
      ),
    ];

    final merged = HiveDatabaseService.mergeRemoteOrders(
      current: current,
      remote: remote,
      queuedOrderIds: const {},
    );

    expect(merged.single.locationId, 'van_wh_7');
    expect(merged.single.listedTotal, 170);
    expect(merged.single.items, hasLength(1));
  });

  group('mergeRemoteInvoices', () {
    InvoiceLineItem invLine() => InvoiceLineItem(
      item: item,
      quantity: 1,
      rate: 10,
      taxPercentage: 5,
    );

    SalesInvoice invoice({
      required String id,
      bool isPendingSync = false,
      String? zohoInvoiceId,
      List<InvoiceLineItem>? items,
    }) => SalesInvoice(
      id: id,
      invoiceNumber: 'INV-1',
      customerId: 'c1',
      customerName: 'Acme',
      date: DateTime(2026, 7, 1),
      dueDate: DateTime(2026, 7, 8),
      items: items ?? [invLine()],
      notes: '',
      isPendingSync: isPendingSync,
      zohoInvoiceId: zohoInvoiceId,
    );

    test(
      'a synced local temp_inv is dropped once remote confirms zohoInvoiceId',
      () {
        final current = [
          invoice(
            id: 'temp_inv_1',
            zohoInvoiceId: 'zoho_inv_1',
          ),
        ];
        final remote = [
          invoice(id: 'zoho_inv_1', items: const [], zohoInvoiceId: 'zoho_inv_1'),
        ];

        final merged = HiveDatabaseService.mergeRemoteInvoices(
          current: current,
          remote: remote,
          queuedInvoiceIds: const {},
        );

        expect(merged, hasLength(1));
        expect(merged.single.id, 'zoho_inv_1');
        expect(merged.single.zohoInvoiceId, 'zoho_inv_1');
        expect(merged.single.isPendingSync, isFalse);
        expect(merged.single.items, hasLength(1));
      },
    );

    test('a still-queued local invoice is kept and remote is not duplicated', () {
      final current = [
        invoice(id: 'temp_inv_1', isPendingSync: true),
      ];
      final remote = [
        invoice(id: 'zoho_other', zohoInvoiceId: 'zoho_other'),
      ];

      final merged = HiveDatabaseService.mergeRemoteInvoices(
        current: current,
        remote: remote,
        queuedInvoiceIds: const {'temp_inv_1'},
      );

      expect(merged.map((i) => i.id), containsAll(['temp_inv_1', 'zoho_other']));
    });
  });
}
