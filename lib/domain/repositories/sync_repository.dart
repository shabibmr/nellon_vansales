import '../../data/models/sync_queue_item.dart';

abstract class SyncRepository {
  Stream<String> get syncStatusStream;
  Stream<int> get syncCountStream;
  bool get isSyncing;
  List<SyncQueueItem> getSyncQueue();
  Future<void> triggerSync();
  Future<void> refreshMasterData();
}
