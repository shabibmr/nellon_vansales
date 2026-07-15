import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/services/sync_worker.dart';
import '../../../../domain/repositories/sync_repository.dart';
import 'masters_sync_event.dart';
import 'masters_sync_state.dart';

class MastersSyncBloc extends Bloc<MastersSyncEvent, MastersSyncState> {
  final SyncRepository syncRepository;
  StreamSubscription<String>? _statusSub;

  MastersSyncBloc({required this.syncRepository})
      : super(MastersSyncState(
          hasCoreMasters: syncRepository.hasCoreMasters(),
        )) {
    on<MastersSyncStarted>(_onStarted);
    on<StatusLogReceived>(_onLogReceived);
    on<SyncOneRequested>(_onSyncOne);
    on<SyncAllRequested>(_onSyncAll);
    on<ClearLogsRequested>(_onClearLogs);
  }

  void _onStarted(MastersSyncStarted event, Emitter<MastersSyncState> emit) {
    _statusSub?.cancel();
    _statusSub = syncRepository.syncStatusStream.listen((status) {
      if (!isClosed) add(StatusLogReceived(status));
    });
    emit(state.copyWith(hasCoreMasters: syncRepository.hasCoreMasters()));
  }

  void _onLogReceived(StatusLogReceived event, Emitter<MastersSyncState> emit) {
    final timestamp = DateTime.now().toLocal().toString().substring(11, 19);
    final logLine = '[$timestamp] ${event.message}';

    final updatedLogs = List<String>.from(state.consoleLogs)..add(logLine);
    if (updatedLogs.length > 100) {
      updatedLogs.removeAt(0);
    }
    emit(state.copyWith(consoleLogs: updatedLogs));
  }

  Future<void> _onSyncOne(
    SyncOneRequested event,
    Emitter<MastersSyncState> emit,
  ) async {
    final type = event.type;
    if (state.inFlight.contains(type) || state.bulkInFlight) return;

    final inFlight = Set<MasterType>.from(state.inFlight)..add(type);
    final lastError = Map<MasterType, String?>.from(state.lastError)
      ..[type] = null;
    final syncedTypes = Set<MasterType>.from(state.syncedTypes)..remove(type);

    emit(state.copyWith(
      inFlight: inFlight,
      lastError: lastError,
      syncedTypes: syncedTypes,
    ));

    try {
      await syncRepository.syncMaster(type);
      if (isClosed) return;
      final newSynced = Set<MasterType>.from(state.syncedTypes)..add(type);
      final newInFlight = Set<MasterType>.from(state.inFlight)..remove(type);
      emit(state.copyWith(
        syncedTypes: newSynced,
        inFlight: newInFlight,
        hasCoreMasters: syncRepository.hasCoreMasters(),
      ));
    } catch (e) {
      if (isClosed) return;
      final newLastError = Map<MasterType, String?>.from(state.lastError)
        ..[type] = e.toString().replaceAll('Exception: ', '');
      final newInFlight = Set<MasterType>.from(state.inFlight)..remove(type);
      emit(state.copyWith(
        lastError: newLastError,
        inFlight: newInFlight,
        hasCoreMasters: syncRepository.hasCoreMasters(),
      ));
    }
  }

  Future<void> _onSyncAll(
    SyncAllRequested event,
    Emitter<MastersSyncState> emit,
  ) async {
    if (state.bulkInFlight) return;

    emit(state.copyWith(
      bulkInFlight: true,
      lastError: {},
      syncedTypes: {},
      bulkSyncStatus: 'Sync in progress...',
      bulkSyncSuccess: null,
    ));

    try {
      for (final type in MasterType.values) {
        if (isClosed) return;

        final inFlight = Set<MasterType>.from(state.inFlight)..add(type);
        final lastError = Map<MasterType, String?>.from(state.lastError)
          ..[type] = null;
        emit(state.copyWith(inFlight: inFlight, lastError: lastError));

        try {
          await syncRepository.syncMaster(type);
          if (isClosed) return;
          final newSynced = Set<MasterType>.from(state.syncedTypes)..add(type);
          emit(state.copyWith(syncedTypes: newSynced));
        } catch (e) {
          if (isClosed) return;
          final newLastError = Map<MasterType, String?>.from(state.lastError)
            ..[type] = e.toString().replaceAll('Exception: ', '');
          emit(state.copyWith(lastError: newLastError));
        } finally {
          if (!isClosed) {
            final newInFlight = Set<MasterType>.from(state.inFlight)
              ..remove(type);
            emit(state.copyWith(inFlight: newInFlight));
          }
        }
      }

      if (isClosed) return;

      final hasMasters = syncRepository.hasCoreMasters();
      if (hasMasters) {
        emit(state.copyWith(
          bulkSyncStatus: 'Master data sync completed successfully!',
          bulkSyncSuccess: true,
          bulkInFlight: false,
          hasCoreMasters: true,
        ));
      } else {
        emit(state.copyWith(
          bulkSyncStatus:
              'Sync completed but some core databases are empty. Try syncing again.',
          bulkSyncSuccess: false,
          bulkInFlight: false,
          hasCoreMasters: false,
        ));
      }
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        bulkSyncStatus: 'Sync failed: $e',
        bulkSyncSuccess: false,
        bulkInFlight: false,
        hasCoreMasters: syncRepository.hasCoreMasters(),
      ));
    }
  }

  void _onClearLogs(ClearLogsRequested event, Emitter<MastersSyncState> emit) {
    emit(state.copyWith(consoleLogs: const []));
  }

  @override
  Future<void> close() {
    _statusSub?.cancel();
    return super.close();
  }
}
