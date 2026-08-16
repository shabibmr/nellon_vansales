import '../../domain/models/item.dart';
import '../../domain/models/stock_transfer.dart';
import '../../domain/models/warehouse.dart';
import '../../domain/repositories/stock_transfer_repository.dart';
import '../models/item_model.dart';
import '../models/stock_transfer_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [StockTransferRepository] backed by
/// [HiveDatabaseService] (local cache) and [ZohoApiClient] (live item stock).
class StockTransferRepositoryImpl implements StockTransferRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  StockTransferRepositoryImpl({required this._dbService, required this._apiClient});

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

  @override
  Future<void> recordStockTransfer(StockTransfer transfer) async {
    await _dbService.saveLocalStockTransfer(transfer);
    await _dbService.enqueueSyncItem(
      SyncQueueItem(
        id: transfer.id,
        type: 'stock_transfer',
        payload: StockTransferModel.fromDomain(transfer).toJson(),
        status: SyncStatus.pending,
        timestamp: DateTime.now(),
      ),
    );
  }
}
