import '../models/sales_order.dart';
import '../models/submit_result.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for local sales-order logging and Zoho sales-order sync.
abstract class SalesOrderRepository {
  /// Gets all sales orders recorded locally.
  List<SalesOrder> getLocalOrders();

  /// Logs a new sales order locally and caches it.
  Future<void> saveLocalOrder(SalesOrder order);

  /// Enqueues a create (`sales_order`) or update (`update_sales_order`) sync
  /// item for [order]. Call after [saveLocalOrder]. Mapping to the queue
  /// payload lives in the data layer so UI/BLoCs stay on domain types.
  Future<void> enqueueSalesOrder(SalesOrder order, {required bool isUpdate});

  /// Downloads sales order **headers** from Zoho Books (list endpoint only —
  /// no per-order detail), merges them into the local cache, and returns the
  /// resulting local list. Line items load via [fetchRemoteOrder] on open.
  /// Omitting the date range pulls unfiltered history; passing one scopes Zoho.
  Future<List<SalesOrder>> fetchRemoteOrders({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Reads a single sales order from Zoho Books by its permanent `zohoOrderId`.
  ///
  /// When [allowOfflineFallback] is true and the remote call fails, returns the
  /// matching local order if present.
  Future<SalesOrder?> fetchRemoteOrder(
    String zohoOrderId, {
    bool allowOfflineFallback = false,
  });

  /// Appends an unsynced transaction item to the local offline synchronization
  /// queue. Used for cross-cutting sync items (e.g. `convert_so`) that don't
  /// fit [enqueueSalesOrder]'s create/update shape.
  Future<void> enqueueSyncItem(SyncQueueItem item);

  /// Builds the sales-order queue item and submits it online-first.
  Future<SubmitResult> submitSalesOrder(
    SalesOrder order, {
    required bool isUpdate,
  });
}
