import 'package:equatable/equatable.dart';
import '../../../../data/services/sync_worker.dart';

class MastersSyncState extends Equatable {
  final Set<MasterType> inFlight;
  final bool bulkInFlight;
  final Map<MasterType, String?> lastError;
  final Set<MasterType> syncedTypes;
  final String? bulkSyncStatus;
  final bool? bulkSyncSuccess;
  final List<String> consoleLogs;

  /// Whether essential masters are present in local cache.
  /// Recomputed after each sync so PROCEED updates without relying on
  /// a non-listenable repository [watch].
  final bool hasCoreMasters;

  const MastersSyncState({
    this.inFlight = const {},
    this.bulkInFlight = false,
    this.lastError = const {},
    this.syncedTypes = const {},
    this.bulkSyncStatus,
    this.bulkSyncSuccess,
    this.consoleLogs = const [],
    this.hasCoreMasters = false,
  });

  bool get canProceed => hasCoreMasters;

  MastersSyncState copyWith({
    Set<MasterType>? inFlight,
    bool? bulkInFlight,
    Map<MasterType, String?>? lastError,
    Set<MasterType>? syncedTypes,
    String? bulkSyncStatus,
    bool? bulkSyncSuccess,
    List<String>? consoleLogs,
    bool? hasCoreMasters,
    bool clearBulkSync = false,
  }) {
    return MastersSyncState(
      inFlight: inFlight ?? this.inFlight,
      bulkInFlight: bulkInFlight ?? this.bulkInFlight,
      lastError: lastError ?? this.lastError,
      syncedTypes: syncedTypes ?? this.syncedTypes,
      bulkSyncStatus:
          clearBulkSync ? null : (bulkSyncStatus ?? this.bulkSyncStatus),
      bulkSyncSuccess:
          clearBulkSync ? null : (bulkSyncSuccess ?? this.bulkSyncSuccess),
      consoleLogs: consoleLogs ?? this.consoleLogs,
      hasCoreMasters: hasCoreMasters ?? this.hasCoreMasters,
    );
  }

  @override
  List<Object?> get props => [
        inFlight,
        bulkInFlight,
        lastError,
        syncedTypes,
        bulkSyncStatus,
        bulkSyncSuccess,
        consoleLogs,
        hasCoreMasters,
      ];
}
