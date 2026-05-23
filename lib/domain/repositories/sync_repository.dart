import '../../data/models/sync_queue_item.dart';
import '../../data/services/sync_worker.dart';

abstract class SyncRepository {
  Stream<String> get syncStatusStream;
  Stream<int> get syncCountStream;
  bool get isSyncing;
  List<SyncQueueItem> getSyncQueue();
  Future<void> triggerSync();
  Future<void> refreshMasterData();
  Future<void> syncMaster(MasterType type);
  bool hasCoreMasters();
}
