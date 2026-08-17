import '../../domain/models/cash_closing.dart';
import '../../domain/repositories/cash_closing_repository.dart';
import '../models/sync_queue_item.dart';
import '../services/hive_database_service.dart';

/// Concrete implementation of [CashClosingRepository] backed by a local Hive database cache.
class CashClosingRepositoryImpl implements CashClosingRepository {
  final HiveDatabaseService _dbService;

  CashClosingRepositoryImpl({required this._dbService});

  @override
  CashClosing? getLocalCashClosing() => _dbService.getLocalCashClosing();

  @override
  Future<void> saveLocalCashClosing(CashClosing closing) =>
      _dbService.saveLocalCashClosing(closing);

  @override
  bool hasPendingCashClosingForToday() =>
      _dbService.hasPendingCashClosingForToday();

  @override
  Future<void> enqueueSyncItem(SyncQueueItem item) =>
      _dbService.enqueueSyncItem(item);
}
