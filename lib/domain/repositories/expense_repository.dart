import '../models/expense_entry.dart';
import '../models/submit_result.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for local expense logging and Zoho expense sync.
abstract class ExpenseRepository {
  /// Gets all route expenses filed locally.
  List<ExpenseEntry> getLocalExpenses();

  /// Saves a new multi-line expense entry locally.
  Future<void> saveLocalExpense(ExpenseEntry expense);

  /// Loads a single expense by id.
  ///
  /// By default uses local cache first, then Zoho. When [forceRemote] is true,
  /// prefers Zoho (and updates the local cache on success).
  ///
  /// [allowOfflineFallback] (default true): if the remote call fails or returns
  /// empty and a local copy exists, return the local copy. Explicit refresh
  /// should pass `false` so network failures surface to the user.
  Future<ExpenseEntry?> fetchExpenseById(
    String expenseId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Downloads expense **headers** from Zoho Books (list endpoint only — no
  /// per-expense detail), merges them into the local cache, and returns the
  /// resulting local list. Lines load via [fetchExpenseById] on open.
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);

  /// Enqueues a create (`expense`) sync item for [expense].
  Future<void> enqueueExpense(ExpenseEntry expense);

  /// Builds the expense queue item and submits it online-first.
  Future<SubmitResult> submitExpense(ExpenseEntry expense);
}
