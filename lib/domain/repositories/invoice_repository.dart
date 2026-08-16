import '../models/sales_invoice.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for local sales-invoice logging and Zoho invoice sync.
abstract class InvoiceRepository {
  /// Gets all sales invoices recorded locally.
  List<SalesInvoice> getLocalInvoices();

  /// Logs a new sales invoice locally and pushes it to local database cache.
  Future<void> saveLocalInvoice(SalesInvoice invoice);

  /// Loads a single invoice by id.
  ///
  /// By default uses local cache first, then Zoho. When [forceRemote] is true,
  /// prefers Zoho (and updates the local cache on success).
  ///
  /// [allowOfflineFallback] (default true): if the remote call fails or returns
  /// empty and a local copy exists, return the local copy. Explicit refresh
  /// should pass `false` so network failures surface to the user.
  Future<SalesInvoice?> fetchInvoiceById(
    String invoiceId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Downloads invoice **headers** from Zoho Books (list endpoint only — no
  /// per-invoice detail), merges them into the local cache, and returns the
  /// resulting local list. Line items load via [fetchInvoiceById] on open.
  Future<List<SalesInvoice>> fetchRemoteInvoices({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);
}
