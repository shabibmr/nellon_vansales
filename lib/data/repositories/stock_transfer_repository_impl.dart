import '../../domain/models/item.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/models/submit_result.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/repositories/stock_transfer_repository.dart';
import '../../domain/utils/stock_transfer_direction.dart';
import '../models/item_model.dart';
import '../models/stock_transfer_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/sync_worker.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [StockTransferRepository] backed by
/// [HiveDatabaseService] (local cache) and [ZohoApiClient] (live item stock).
class StockTransferRepositoryImpl implements StockTransferRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;
  final SyncWorker? _syncWorker;

  StockTransferRepositoryImpl({
    required HiveDatabaseService dbService,
    required ZohoApiClient apiClient,
    SyncWorker? syncWorker,
  }) : _dbService = dbService,
       _apiClient = apiClient,
       _syncWorker = syncWorker;

  SyncWorker get _worker {
    final worker = _syncWorker;
    if (worker == null) {
      throw StateError('submit* requires SyncWorker');
    }
    return worker;
  }

  @override
  Future<({List<Item> items, bool live})> loadCurrentLocationItems() async {
    final locationId = _dbService.assignedWarehouseId ?? '';
    try {
      final raw = await _apiClient.fetchItems(locationId);
      final items = raw.map((json) => ItemModel.fromJson(json)).toList();
      return (items: items, live: true);
    } catch (_) {
      return (items: _dbService.getItems(), live: false);
    }
  }

  @override
  List<Item> getItems() => _dbService.getItems();

  @override
  Map<String, double> getTodaysInvoicedQuantities({DateTime? asOf}) {
    final target = asOf ?? DateTime.now();
    final invoiceQtyByItem = <String, double>{};
    for (final inv in _dbService.getLocalInvoices()) {
      if (!_isSameDay(inv.date, target)) continue;
      for (final line in inv.items) {
        invoiceQtyByItem[line.item.id] =
            (invoiceQtyByItem[line.item.id] ?? 0) + line.quantityInBase;
      }
    }
    return invoiceQtyByItem;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final locA = a.toLocal();
    final locB = b.toLocal();
    return locA.year == locB.year &&
        locA.month == locB.month &&
        locA.day == locB.day;
  }

  @override
  ({Warehouse defaultWarehouse, Warehouse currentLocation})
  resolveTransferLocations() {
    return (
      defaultWarehouse: _resolveDefaultWarehouse(),
      currentLocation: _resolveCurrentLocation(),
    );
  }

  /// Resolves the organization's default (primary) warehouse location, falling
  /// back to the first known warehouse if none is flagged primary.
  Warehouse _resolveDefaultWarehouse() {
    final warehouses = _dbService.getWarehouses();
    if (warehouses.isEmpty) {
      return const Warehouse(id: '', name: 'Default Warehouse', address: '');
    }
    final primaryId = _dbService.primaryWarehouseId;
    if (primaryId != null && primaryId.isNotEmpty) {
      for (final w in warehouses) {
        if (w.id == primaryId) return w;
      }
    }
    return warehouses.firstWhere(
      (w) => w.isPrimary,
      orElse: () => warehouses.first,
    );
  }

  Warehouse _resolveCurrentLocation() {
    final id = _dbService.assignedWarehouseId;
    final warehouses = _dbService.getWarehouses();
    return warehouses.firstWhere(
      (w) => w.id == id,
      orElse: () =>
          Warehouse(id: id ?? '', name: 'Current Location', address: ''),
    );
  }

  SyncQueueItem _stockTransferItem(
    StockTransfer transfer, {
    required bool isUpdate,
  }) {
    final payload = StockTransferModel.fromDomain(transfer).toJson();
    if (isUpdate) {
      final zohoId = transfer.zohoTransferId;
      if (zohoId == null || zohoId.isEmpty) {
        throw StateError(
          'Cannot update a stock transfer with no zohoTransferId',
        );
      }
      // toJson() always stamps `transfer_order_id` with the *local* id (it
      // doubles as the local round-trip key alongside `id`) — overwrite it
      // with the real Zoho id so the PUT targets the right transfer order.
      payload['transfer_order_id'] = zohoId;
    } else {
      // Creating: `transfer_order_id` here is only the local temp id, never
      // a real Zoho id — strip it so it can't leak into the POST body.
      // `id` (same local value) is still present for local round-trip.
      payload.remove('transfer_order_id');
    }
    return SyncQueueItem(
      id: transfer.id,
      type: isUpdate ? 'update_stock_transfer' : 'stock_transfer',
      payload: payload,
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<void> recordStockTransfer(StockTransfer transfer) async {
    await _dbService.saveLocalStockTransfer(transfer);
    await enqueueStockTransfer(transfer, isUpdate: false);
  }

  @override
  Future<void> enqueueStockTransfer(
    StockTransfer transfer, {
    required bool isUpdate,
  }) {
    return _dbService.enqueueSyncItem(
      _stockTransferItem(transfer, isUpdate: isUpdate),
    );
  }

  @override
  Future<SubmitResult> submitStockTransfer(
    StockTransfer transfer, {
    bool isUpdate = false,
  }) {
    return _worker.submitOrEnqueue(
      _stockTransferItem(transfer, isUpdate: isUpdate),
    );
  }

  /// Van location written at login (`Salesperson.locationId`), falling back
  /// to the session `assignedWarehouseId` if the salesperson row is missing.
  String? get _appLocationId {
    final fromSalesperson = _dbService.getCurrentSalesperson()?.locationId;
    if (fromSalesperson != null && fromSalesperson.isNotEmpty) {
      return fromSalesperson;
    }
    final assigned = _dbService.assignedWarehouseId;
    if (assigned != null && assigned.isNotEmpty) return assigned;
    return null;
  }

  @override
  List<StockTransfer> getLocalStockTransfers() =>
      _dbService.getLocalStockTransfers();

  @override
  Future<List<StockTransfer>> fetchRemoteStockTransfers({
    DateTime? startDate,
    DateTime? endDate,
    required StockTransferDirection direction,
  }) async {
    final locationId = _appLocationId;
    if (locationId == null) {
      throw Exception(
        'Unable to resolve your van location. Please sync masters and re-select your route.',
      );
    }

    final raw = await _apiClient.fetchStockTransfers(
      startDate: startDate,
      endDate: endDate,
      fromLocationId: direction == StockTransferDirection.unload
          ? locationId
          : null,
      toLocationId: direction == StockTransferDirection.load
          ? locationId
          : null,
    );

    final remote = raw.map((json) {
      final mapped = StockTransferModel.fromJson(json);
      return mapped.copyWith(
        direction: inferStockTransferDirection(
          fromLocationId: mapped.fromLocationId,
          toLocationId: mapped.toLocationId,
          vanLocationId: locationId,
          stored: direction,
        ),
      );
    }).toList();

    await _dbService.saveRemoteStockTransfers(remote);
    return _dbService
        .getLocalStockTransfers()
        .where((t) => t.direction == direction)
        .toList();
  }
}
