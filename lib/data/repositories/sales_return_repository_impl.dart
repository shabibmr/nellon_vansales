import '../../domain/models/sales_return.dart';
import '../../domain/models/submit_result.dart';
import '../../domain/repositories/sales_return_repository.dart';
import '../models/sales_return_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/sync_worker.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [SalesReturnRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class SalesReturnRepositoryImpl implements SalesReturnRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;
  final SyncWorker? _syncWorker;

  SalesReturnRepositoryImpl({
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

  SyncQueueItem _returnItem(SalesReturn salesReturn) {
    return SyncQueueItem(
      id: salesReturn.id,
      type: 'return',
      payload: _returnQueuePayload(salesReturn),
      status: SyncStatus.pending,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> _returnQueuePayload(SalesReturn salesReturn) {
    final payload = SalesReturnModel.fromDomain(salesReturn).toJson();
    final lines = payload['line_items'];
    if (lines is! List) return payload;
    payload['line_items'] = lines.map((entry) {
      if (entry is! Map) return entry;
      final map = Map<String, dynamic>.from(entry);
      final resolved = _resolvedInvoiceId(map['invoice_id']?.toString());
      if (resolved != null) map['invoice_id'] = resolved;
      return map;
    }).toList();
    return payload;
  }

  String? _resolvedInvoiceId(String? localOrRemoteId) {
    if (localOrRemoteId == null || localOrRemoteId.isEmpty) {
      return localOrRemoteId;
    }
    for (final inv in _dbService.getAllLocalInvoicesUnfiltered()) {
      if (inv.id == localOrRemoteId) {
        final zohoId = inv.zohoInvoiceId;
        if (zohoId != null && zohoId.isNotEmpty) return zohoId;
        return localOrRemoteId;
      }
    }
    return localOrRemoteId;
  }

  @override
  Future<void> enqueueSalesReturn(SalesReturn salesReturn) {
    return _dbService.enqueueSyncItem(_returnItem(salesReturn));
  }

  @override
  Future<SubmitResult> submitSalesReturn(SalesReturn salesReturn) {
    return _worker.submitOrEnqueue(_returnItem(salesReturn));
  }
}
