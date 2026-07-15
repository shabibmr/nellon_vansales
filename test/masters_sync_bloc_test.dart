import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/ui/features/sync/bloc/masters_sync_bloc.dart';
import 'package:van_sales/ui/features/sync/bloc/masters_sync_event.dart';

class FakeSyncRepository implements SyncRepository {
  final _statusController = StreamController<String>.broadcast();
  List<MasterType> syncedMasters = [];
  bool throwOnSync = false;
  bool coreMastersResult = true;

  @override
  Stream<String> get syncStatusStream => _statusController.stream;

  void emitStatus(String status) {
    _statusController.add(status);
  }

  @override
  Future<void> syncMaster(MasterType type) async {
    syncedMasters.add(type);
    if (throwOnSync) {
      throw Exception('Sync failed');
    }
  }

  @override
  bool hasCoreMasters() => coreMastersResult;

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {}
  @override
  Future<void> clearFailedSyncItems() async {}
  @override
  Stream<int> get syncCountStream => const Stream.empty();
  @override
  bool get isSyncing => false;
  @override
  List<SyncQueueItem> getSyncQueue() => [];
  @override
  Future<void> refreshMasterData() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncRepository syncRepo;
  late MastersSyncBloc bloc;

  setUp(() {
    syncRepo = FakeSyncRepository();
    bloc = MastersSyncBloc(syncRepository: syncRepo);
  });

  tearDown(() {
    bloc.close();
  });

  test('Initial state seeds hasCoreMasters from repository', () {
    expect(bloc.state.inFlight, isEmpty);
    expect(bloc.state.bulkInFlight, isFalse);
    expect(bloc.state.consoleLogs, isEmpty);
    expect(bloc.state.hasCoreMasters, isTrue);
    expect(bloc.state.canProceed, isTrue);
  });

  test('Initial hasCoreMasters is false when masters are missing', () {
    syncRepo.coreMastersResult = false;
    final emptyBloc = MastersSyncBloc(syncRepository: syncRepo);
    expect(emptyBloc.state.hasCoreMasters, isFalse);
    expect(emptyBloc.state.canProceed, isFalse);
    emptyBloc.close();
  });

  test('MastersSyncStarted listens to status stream and appends formatted console logs', () async {
    bloc.add(MastersSyncStarted());
    // Give subscription time to attach
    await Future.delayed(Duration.zero);

    final logFuture = bloc.stream.first;
    syncRepo.emitStatus('Fetching customers...');
    final state = await logFuture;

    expect(state.consoleLogs.length, 1);
    expect(state.consoleLogs.first, contains('Fetching customers...'));
  });

  test('SyncOneRequested tracks individual in-flight progress and records success', () async {
    final syncFuture = bloc.stream.firstWhere((s) => s.syncedTypes.contains(MasterType.customers));
    bloc.add(const SyncOneRequested(MasterType.customers));
    final state = await syncFuture;

    expect(syncRepo.syncedMasters, [MasterType.customers]);
    expect(state.inFlight, isEmpty);
    expect(state.lastError[MasterType.customers], isNull);
    expect(state.hasCoreMasters, isTrue);
  });

  test('SyncOneRequested flips canProceed when masters become available', () async {
    syncRepo.coreMastersResult = false;
    await bloc.close();
    bloc = MastersSyncBloc(syncRepository: syncRepo);
    expect(bloc.state.canProceed, isFalse);

    // After sync, repository reports masters present.
    syncRepo.coreMastersResult = true;
    final syncFuture = bloc.stream.firstWhere((s) => s.canProceed);
    bloc.add(const SyncOneRequested(MasterType.items));
    final state = await syncFuture;

    expect(state.hasCoreMasters, isTrue);
    expect(state.canProceed, isTrue);
  });

  test('SyncOneRequested captures errors and sets them on the state', () async {
    syncRepo.throwOnSync = true;
    final syncFuture = bloc.stream.firstWhere((s) => s.lastError[MasterType.customers] != null);
    bloc.add(const SyncOneRequested(MasterType.customers));
    final state = await syncFuture;

    expect(state.inFlight, isEmpty);
    expect(state.lastError[MasterType.customers], 'Sync failed');
    expect(state.syncedTypes, isEmpty);
  });

  test('SyncAllRequested sequentially fetches all MasterTypes and completes with success status', () async {
    final syncFuture = bloc.stream.firstWhere((s) => s.bulkSyncSuccess == true);
    bloc.add(SyncAllRequested());
    final state = await syncFuture;

    expect(syncRepo.syncedMasters.length, MasterType.values.length);
    expect(state.bulkInFlight, isFalse);
    expect(state.bulkSyncSuccess, isTrue);
    expect(state.bulkSyncStatus, 'Master data sync completed successfully!');
    expect(state.hasCoreMasters, isTrue);
    expect(state.canProceed, isTrue);
  });

  test('SyncAllRequested sets canProceed false when core masters still empty', () async {
    syncRepo.coreMastersResult = false;
    await bloc.close();
    bloc = MastersSyncBloc(syncRepository: syncRepo);

    final syncFuture = bloc.stream.firstWhere((s) => s.bulkSyncSuccess == false);
    bloc.add(SyncAllRequested());
    final state = await syncFuture;

    expect(state.bulkInFlight, isFalse);
    expect(state.hasCoreMasters, isFalse);
    expect(state.canProceed, isFalse);
  });
}
