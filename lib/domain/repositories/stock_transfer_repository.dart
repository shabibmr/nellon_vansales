import '../models/item.dart';
import '../models/stock_transfer.dart';
import '../models/submit_result.dart';
import '../models/warehouse.dart';

/// Abstract contract for the Issue-to-Van / Stock-Unloading transfer workflow.
abstract class StockTransferRepository {
  /// Current-location item stock, preferring a live Zoho fetch and falling
  /// back to the local cache on failure.
  Future<({List<Item> items, bool live})> loadCurrentLocationItems();

  /// Local item cache only (Stock Unloading's source of truth, and the
  /// backfill source for demand items missing from [loadCurrentLocationItems]).
  List<Item> getItems();

  /// Invoiced quantity per item id for [asOf] (defaults to today), scoped
  /// to the current location.
  Map<String, double> getTodaysInvoicedQuantities({DateTime? asOf});

  /// Both ends of a transfer: the org's default warehouse and the van's
  /// current location, each resolved with its fallback rule applied.
  ({Warehouse defaultWarehouse, Warehouse currentLocation})
  resolveTransferLocations();

  /// Persists [transfer] locally and enqueues it for sync.
  Future<void> recordStockTransfer(StockTransfer transfer);

  /// Enqueues a create (`stock_transfer`) sync item for [transfer].
  Future<void> enqueueStockTransfer(StockTransfer transfer);

  /// Builds the stock-transfer queue item and submits it online-first.
  Future<SubmitResult> submitStockTransfer(StockTransfer transfer);
}
