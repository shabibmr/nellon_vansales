import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';

// --- Events ---
abstract class SyncEvent extends Equatable {
  const SyncEvent();
  @override
  List<Object?> get props => [];
}

class SyncStarted extends SyncEvent {}

class TriggerSync extends SyncEvent {}

class RefreshMasterDataRequested extends SyncEvent {}

class SyncStatusUpdated extends SyncEvent {
  final String statusMessage;
  const SyncStatusUpdated(this.statusMessage);
  @override
  List<Object?> get props => [statusMessage];
}

class PendingQueueCountUpdated extends SyncEvent {
  final int count;
  const PendingQueueCountUpdated(this.count);
  @override
  List<Object?> get props => [count];
}

// --- States ---
class SyncState extends Equatable {
  final String statusMessage;
  final int pendingCount;
  final bool isSyncing;
  final List<SyncQueueItem> queueItems;

  const SyncState({
    this.statusMessage = 'Idle',
    this.pendingCount = 0,
    this.isSyncing = false,
    this.queueItems = const [],
  });

  SyncState copyWith({
    String? statusMessage,
    int? pendingCount,
    bool? isSyncing,
    List<SyncQueueItem>? queueItems,
  }) {
    return SyncState(
      statusMessage: statusMessage ?? this.statusMessage,
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      queueItems: queueItems ?? this.queueItems,
    );
  }

  @override
  List<Object?> get props => [statusMessage, pendingCount, isSyncing, queueItems];
}

// --- Bloc ---
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncRepository _syncRepository;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<int>? _countSubscription;

  SyncBloc({
    required SyncRepository this._syncRepository,
  })  : super(const SyncState()) {
    on<SyncStarted>(_onSyncStarted);
    on<TriggerSync>(_onTriggerSync);
    on<RefreshMasterDataRequested>(_onRefreshMasterDataRequested);
    on<SyncStatusUpdated>(_onSyncStatusUpdated);
    on<PendingQueueCountUpdated>(_onPendingQueueCountUpdated);
  }

  void _onSyncStarted(SyncStarted event, Emitter<SyncState> emit) {
    // Initial load
    final queue = _syncRepository.getSyncQueue();
    final pendingCount = queue.where((x) => x.status != SyncStatus.completed).length;

    emit(state.copyWith(
      pendingCount: pendingCount,
      queueItems: queue,
      statusMessage: pendingCount > 0 ? '$pendingCount items pending sync' : 'All transactions are synced',
    ));

    // Cancel old subscriptions
    _statusSubscription?.cancel();
    _countSubscription?.cancel();

    // Subscribe to streams
    _statusSubscription = _syncRepository.syncStatusStream.listen((status) {
      add(SyncStatusUpdated(status));
    });

    _countSubscription = _syncRepository.syncCountStream.listen((count) {
      add(PendingQueueCountUpdated(count));
    });
  }

  Future<void> _onTriggerSync(TriggerSync event, Emitter<SyncState> emit) async {
    emit(state.copyWith(isSyncing: true, statusMessage: 'Connecting...'));
    await _syncRepository.triggerSync();
    final queue = _syncRepository.getSyncQueue();
    emit(state.copyWith(
      isSyncing: _syncRepository.isSyncing,
      queueItems: queue,
    ));
  }

  Future<void> _onRefreshMasterDataRequested(RefreshMasterDataRequested event, Emitter<SyncState> emit) async {
    emit(state.copyWith(isSyncing: true, statusMessage: 'Fetching latest master lists from Zoho...'));
    await _syncRepository.refreshMasterData();
    emit(state.copyWith(isSyncing: false, statusMessage: 'Master lists refreshed!'));
  }

  void _onSyncStatusUpdated(SyncStatusUpdated event, Emitter<SyncState> emit) {
    final queue = _syncRepository.getSyncQueue();
    emit(state.copyWith(
      statusMessage: event.statusMessage,
      isSyncing: _syncRepository.isSyncing,
      queueItems: queue,
    ));
  }

  void _onPendingQueueCountUpdated(PendingQueueCountUpdated event, Emitter<SyncState> emit) {
    final queue = _syncRepository.getSyncQueue();
    emit(state.copyWith(
      pendingCount: event.count,
      queueItems: queue,
    ));
  }

  @override
  Future<void> close() {
    _statusSubscription?.cancel();
    _countSubscription?.cancel();
    return super.close();
  }
}
