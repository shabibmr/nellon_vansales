import '../models/sales_return.dart';
import '../models/submit_result.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for local sales-return (credit note) logging and Zoho sync.
abstract class SalesReturnRepository {
  /// Gets all sales returns logged locally.
  List<SalesReturn> getLocalReturns();

  /// Logs a credit note/sales return locally and caches it.
  Future<void> saveLocalReturn(SalesReturn salesReturn);

  /// Loads a single sales return (credit note) by id.
  ///
  /// By default uses local cache first, then Zoho. When [forceRemote] is true,
  /// prefers Zoho (and updates the local cache on success).
  ///
  /// [allowOfflineFallback] (default true): if the remote call fails or returns
  /// empty and a local copy exists, return the local copy. Explicit refresh
  /// should pass `false` so network failures surface to the user.
  Future<SalesReturn?> fetchSalesReturnById(
    String creditNoteId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Downloads sales return **headers** from Zoho Books (list endpoint only —
  /// no per-return detail), merges them into the local cache, and returns the
  /// resulting local list. Line items load via [fetchSalesReturnById] on open.
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);

  /// Enqueues a create (`return`) sync item for [salesReturn].
  Future<void> enqueueSalesReturn(SalesReturn salesReturn);

  /// Builds the return queue item and submits it online-first.
  Future<SubmitResult> submitSalesReturn(SalesReturn salesReturn);
}
