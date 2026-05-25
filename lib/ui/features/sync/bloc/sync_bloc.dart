import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/repositories/sync_repository.dart';
import '../../../../data/models/sync_queue_item.dart';

// --- Events ---

/// Base class for all sync-related events processed by [SyncBloc].
abstract class SyncEvent extends Equatable {
  const SyncEvent();
  @override
  List<Object?> get props => [];
}

/// Fired on BLoC instantiation to establish status and count stream listeners from SyncRepository.
class SyncStarted extends SyncEvent {}

/// Fired to trigger an immediate upload sweep of all pending transaction queue tasks.
class TriggerSync extends SyncEvent {}

/// Fired to request a full master data cache refresh sequence from Zoho Books.
class RefreshMasterDataRequested extends SyncEvent {}

/// Fired internally by stream listeners to update the active synchronization status text.
class SyncStatusUpdated extends SyncEvent {
  /// The updated status string.
  final String statusMessage;

  /// Creates a [SyncStatusUpdated] event.
  const SyncStatusUpdated(this.statusMessage);
  @override
  List<Object?> get props => [statusMessage];
}

/// Fired internally by stream listeners to update the remaining unsynced queue task counts.
class PendingQueueCountUpdated extends SyncEvent {
  /// Remaining items count.
  final int count;

  /// Creates a [PendingQueueCountUpdated] event.
  const PendingQueueCountUpdated(this.count);
  @override
  List<Object?> get props => [count];
}

// --- States ---

/// Holds state variables representing sync status logs, pending items counts, and current running queues.
class SyncState extends Equatable {
  /// Text message explaining sync state.
  final String statusMessage;

  /// Number of pending unsynced queue items.
  final int pendingCount;

  /// Loader flag indicating if a sync sequence is actively executing.
  final bool isSyncing;

  /// The active sync queue items cache.
  final List<SyncQueueItem> queueItems;

  /// Creates a [SyncState].
  const SyncState({
    this.statusMessage = 'Idle',
    this.pendingCount = 0,
    this.isSyncing = false,
    this.queueItems = const [],
  });

  /// Returns a copy of [SyncState] with replaced values for specified fields.
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

/// Business Logic Component coordinating background sync triggers and monitoring queues.
///
/// Drives dashboard status notifications, master updates, and maps stream subscriptions.
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncRepository _syncRepository;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<int>? _countSubscription;

  /// Instantiates a new [SyncBloc] mapping sync streams.
  SyncBloc({
    required this._syncRepository,
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
