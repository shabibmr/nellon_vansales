import 'package:equatable/equatable.dart';
import '../../../../data/services/sync_worker.dart';

abstract class MastersSyncEvent extends Equatable {
  const MastersSyncEvent();

  @override
  List<Object?> get props => [];
}

class MastersSyncStarted extends MastersSyncEvent {}

class StatusLogReceived extends MastersSyncEvent {
  final String message;

  const StatusLogReceived(this.message);

  @override
  List<Object?> get props => [message];
}

class SyncOneRequested extends MastersSyncEvent {
  final MasterType type;

  const SyncOneRequested(this.type);

  @override
  List<Object?> get props => [type];
}

class SyncAllRequested extends MastersSyncEvent {}

class ClearLogsRequested extends MastersSyncEvent {}
