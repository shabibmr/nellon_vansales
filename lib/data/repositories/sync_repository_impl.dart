import '../../domain/repositories/sync_repository.dart';
import '../models/sync_queue_item.dart';
import '../services/sync_worker.dart';
import '../services/hive_database_service.dart';

class SyncRepositoryImpl implements SyncRepository {
  final SyncWorker _syncWorker;
  final HiveDatabaseService _dbService;

  SyncRepositoryImpl({
    required SyncWorker this._syncWorker,
    required HiveDatabaseService this._dbService,
  });

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
}
