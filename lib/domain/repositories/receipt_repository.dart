import '../models/open_invoice.dart';
import '../models/receipt_voucher.dart';
import '../../data/models/sync_queue_item.dart';

/// Abstract contract for local receipt/collection logging, Zoho receipt sync,
/// and the open-invoice balances receipts allocate against.
abstract class ReceiptRepository {
  /// Gets all receipt vouchers collected locally.
  List<ReceiptVoucher> getLocalReceipts();

  /// Logs a new collection receipt locally and caches it.
  Future<void> saveLocalReceipt(ReceiptVoucher voucher);

  /// Loads a single receipt/payment by id.
  ///
  /// By default uses local cache first, then Zoho. When [forceRemote] is true,
  /// prefers Zoho (and updates the local cache on success).
  ///
  /// [allowOfflineFallback] (default true): if the remote call fails or returns
  /// empty and a local copy exists, return the local copy. Explicit refresh
  /// should pass `false` so network failures surface to the user.
  Future<ReceiptVoucher?> fetchReceiptById(
    String paymentId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  });

  /// Downloads receipt **headers** from Zoho Books, merges them into the local
  /// cache, and returns the resulting local list. Invoice allocations load via
  /// [fetchReceiptById] when the editor opens.
  Future<List<ReceiptVoucher>> fetchRemoteReceipts({
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Retrieves open (unpaid) customer invoices from the local cache, if any.
  /// Prefer [fetchRemoteOpenInvoices] for live balances when online.
  List<OpenInvoice> getOpenInvoices({String? customerId});

  /// Fetches open (unpaid) invoices live from Zoho Books.
  ///
  /// When [customerId] is set, scopes the request to that customer. Results are
  /// also written into the local open-invoice cache so offline UI can fall back
  /// to the last successful live fetch.
  Future<List<OpenInvoice>> fetchRemoteOpenInvoices({String? customerId});

  /// Appends an unsynced transaction item to the local offline synchronization queue.
  Future<void> enqueueSyncItem(SyncQueueItem item);
}
