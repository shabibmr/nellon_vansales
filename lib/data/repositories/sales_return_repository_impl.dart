import '../../domain/models/sales_return.dart';
import '../../domain/repositories/sales_return_repository.dart';
import '../models/sales_return_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SalesReturnRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class SalesReturnRepositoryImpl implements SalesReturnRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  SalesReturnRepositoryImpl({
    required this._dbService,
    required this._apiClient,
  });

  @override
  List<SalesReturn> getLocalReturns() => _dbService.getLocalReturns();

  @override
  Future<void> saveLocalReturn(SalesReturn salesReturn) =>
      _dbService.saveLocalReturn(salesReturn);

  @override
  Future<SalesReturn?> fetchSalesReturnById(
    String creditNoteId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (creditNoteId.isEmpty) return null;
    SalesReturn? local;
    for (final ret in _dbService.getLocalReturns()) {
      if (ret.id == creditNoteId) {
        local = ret;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    try {
      final json = await _apiClient.fetchSalesReturnDetail(creditNoteId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = SalesReturnModel.fromJson(json);
      await _dbService.saveRemoteReturns([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  @override
  Future<List<SalesReturn>> fetchRemoteReturns({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Header-only list path (no per-return detail). Full line items load
    // lazily via [fetchSalesReturnById] when the editor opens.
    final raw = await _apiClient.fetchSalesReturnHeaders(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final returns = raw.map((json) {
      final ret = _returnFromZoho(json);
      if (vanId == null || vanId.isEmpty) return ret;
      return ret.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteReturns(returns);
    return _dbService.getLocalReturns();
  }

  /// Zoho header `location_id` is org primary, not van warehouse.
  SalesReturn _returnFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map.remove('location_id');
    return SalesReturnModel.fromJson(map);
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);
}
