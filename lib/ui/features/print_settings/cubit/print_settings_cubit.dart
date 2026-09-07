import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/models/print_settings.dart';
import '../../../../domain/repositories/print_settings_repository.dart';

/// App-wide supervisor phone from cached Firestore `server_config/print`.
class PrintSettingsCubit extends Cubit<PrintSettings> {
  PrintSettingsCubit({required PrintSettingsRepository repository})
      : _repository = repository,
        super(PrintSettings(supervisorPhone: repository.supervisorPhone)) {
    hydrateDone = _start();
  }

  final PrintSettingsRepository _repository;
  late final Future<void> hydrateDone;

  String get supervisorPhone => state.resolvedPhone;

  Future<void> _start() async {
    await _repository.hydrate();
    if (!isClosed) {
      emit(PrintSettings(supervisorPhone: _repository.supervisorPhone));
    }
    await _repository.refresh();
    if (!isClosed) {
      emit(PrintSettings(supervisorPhone: _repository.supervisorPhone));
    }
  }
}
