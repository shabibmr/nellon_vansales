import '../models/cash_closing.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for filing and tracking the daily cash closing reconciliation.
abstract class CashClosingRepository {
  /// Retrieves the most recently filed cash closing, if any.
  CashClosing? getLocalCashClosing();

  /// Saves/updates the end-of-trip daily cash closing.
  Future<void> saveLocalCashClosing(CashClosing closing);

  /// True when today's sales activity still needs cash closing.
  bool hasPendingCashClosingForToday();

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);
}
