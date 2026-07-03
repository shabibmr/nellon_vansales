import '../../domain/repositories/sync_repository.dart';
import '../models/sync_queue_item.dart';
import '../services/sync_worker.dart';
import '../services/hive_database_service.dart';

/// Concrete implementation of [SyncRepository].
///
/// Combines [SyncWorker] background jobs and [HiveDatabaseService] queries to trigger and monitor sync sequences.
class SyncRepositoryImpl implements SyncRepository {
  final SyncWorker _syncWorker;
  final HiveDatabaseService _dbService;

  /// Creates a new [SyncRepositoryImpl] with required worker and local database service.
  SyncRepositoryImpl({required this._syncWorker, required this._dbService});

  @override
  Stream<String> get syncStatusStream => _syncWorker.syncStatusStream;

  @override
  Stream<int> get syncCountStream => _syncWorker.syncCountStream;

  @override
  bool get isSyncing => _syncWorker.isSyncing;

  @override
  List<SyncQueueItem> getSyncQueue() {
    return _dbService.getSyncQueue();
  }

  @override
  Future<void> triggerSync() {
    return _syncWorker.syncPendingItems();
  }

  @override
  Future<void> refreshMasterData() {
    return _syncWorker.refreshMasterData();
  }

  @override
  Future<void> syncMaster(MasterType type) {
    return _syncWorker.syncMaster(type);
  }

  @override
  bool hasCoreMasters() {
    return _dbService.getItems().isNotEmpty;
  }
}
