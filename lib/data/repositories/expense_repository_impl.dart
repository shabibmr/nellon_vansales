import '../../domain/models/expense_entry.dart';
import '../../domain/repositories/expense_repository.dart';
import '../models/expense_entry_model.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';
import '../services/zoho_api_client.dart';

/// Concrete implementation of [ExpenseRepository] backed by a local Hive
/// database cache and the Zoho Books API.
class ExpenseRepositoryImpl implements ExpenseRepository {
  final HiveDatabaseService _dbService;
  final ZohoApiClient _apiClient;

  ExpenseRepositoryImpl({required this._dbService, required this._apiClient});

  @override
  List<ExpenseEntry> getLocalExpenses() => _dbService.getLocalExpenses();

  @override
  Future<void> saveLocalExpense(ExpenseEntry expense) =>
      _dbService.saveLocalExpense(expense);

  @override
  Future<ExpenseEntry?> fetchExpenseById(
    String expenseId, {
    bool forceRemote = false,
    bool allowOfflineFallback = true,
  }) async {
    if (expenseId.isEmpty) return null;
    ExpenseEntry? local;
    for (final exp in _dbService.getLocalExpenses()) {
      if (exp.id == expenseId) {
        local = exp;
        break;
      }
    }
    if (!forceRemote && local != null) return local;

    try {
      final json = await _apiClient.fetchExpenseDetail(expenseId);
      if (json.isEmpty) {
        if (allowOfflineFallback && local != null) return local;
        return null;
      }
      final remote = _expenseFromZoho(json);
      await _dbService.saveRemoteExpenses([remote]);
      return remote;
    } catch (_) {
      if (allowOfflineFallback && local != null) return local;
      rethrow;
    }
  }

  /// Zoho header `location_id` is org primary, not van warehouse.
  ExpenseEntry _expenseFromZoho(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map.remove('location_id');
    return ExpenseEntryModel.fromZohoJson(map);
  }

  @override
  Future<List<ExpenseEntry>> fetchRemoteExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Header-only list path (no per-expense detail). Full line items load
    // lazily via [fetchExpenseById] when the editor opens.
    final raw = await _apiClient.fetchExpenseHeaders(
      startDate: startDate,
      endDate: endDate,
    );
    final vanId = _dbService.assignedWarehouseId;
    final remote = raw.map((json) {
      final exp = _expenseFromZoho(json);
      if (vanId == null || vanId.isEmpty) return exp;
      return exp.copyWith(locationId: vanId);
    }).toList();
    await _dbService.saveRemoteExpenses(remote);
    // Zoho scopes via paid_through_account_id; local cache is only
    // location-filtered and can still hold other salesmen's rows from older
    // unscoped pulls. Prefer the API set plus this device's pending drafts.
    final byId = <String, ExpenseEntry>{for (final e in remote) e.id: e};
    for (final local in _dbService.getLocalExpenses()) {
      if (local.isPendingSync) {
        byId.putIfAbsent(local.id, () => local);
      }
    }
    return byId.values.toList();
  }

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);
}
