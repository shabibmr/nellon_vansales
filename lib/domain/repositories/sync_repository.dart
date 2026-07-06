import '../../data/models/sync_queue_item.dart';
import '../../data/services/sync_worker.dart';

/// Abstract contract managing offline-first data synchronization and core master status.
///
/// Drives background sync queues, triggers Zoho master refreshes, and exposes streams
/// to monitor synchronizing state, count, and progress.
abstract class SyncRepository {
  /// Stream broadcasting descriptive status updates of the current sync run.
  Stream<String> get syncStatusStream;

  /// Stream broadcasting the remaining/completed item count inside the current sync queue.
  Stream<int> get syncCountStream;

  /// Returns true if a synchronization process is actively executing.
  bool get isSyncing;

  /// Retrieves a snapshot of the current local offline-queue.
  List<SyncQueueItem> getSyncQueue();

  /// Initiates an upload of all pending local transactions in the offline-queue to Zoho Books.
  ///
  /// By default, previously-failed items are only retried if they were
  /// transient and their exponential backoff window has elapsed. Pass
  /// [forceRetryAll] (from a manual "Retry Failed" UI action) to retry every
  /// failed item immediately regardless of backoff or error category.
  Future<void> triggerSync({bool forceRetryAll = false});

  /// Removes every queue task currently marked as failed, without touching pending/syncing items.
  Future<void> clearFailedSyncItems();

  /// Triggers a full master data download (Customers, Items, Taxes, Warehouses) from Zoho Books.
  Future<void> refreshMasterData();

  /// Triggers a download/refresh for a specific master data type.
  Future<void> syncMaster(MasterType type);

  /// Returns true if essential master data lists (Customers, Items, Routes) are populated in local cache.
  bool hasCoreMasters();
}
