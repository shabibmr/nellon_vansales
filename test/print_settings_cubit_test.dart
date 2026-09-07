import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/print_settings.dart';
import 'package:van_sales/domain/repositories/print_settings_repository.dart';
import 'package:van_sales/ui/features/print_settings/cubit/print_settings_cubit.dart';

class FakePrintSettingsRepository implements PrintSettingsRepository {
  FakePrintSettingsRepository([
    this._phone = PrintSettings.fallbackSupervisorPhone,
  ]);

  String _phone;
  String hydratePhone = '+971 50 111 1111';
  String refreshPhone = '+971 50 222 2222';

  @override
  String get supervisorPhone => _phone;

  @override
  Future<void> hydrate() async {
    _phone = hydratePhone;
  }

  @override
  Future<PrintSettings> refresh() async {
    _phone = refreshPhone;
    return PrintSettings(supervisorPhone: _phone);
  }
}

void main() {
  group('PrintSettingsCubit', () {
    late FakePrintSettingsRepository repository;
    late PrintSettingsCubit cubit;

    setUp(() {
      repository = FakePrintSettingsRepository();
      cubit = PrintSettingsCubit(repository: repository);
    });

    tearDown(() => cubit.close());

    test('hydrates from cache then refreshes from Firestore', () async {
      await cubit.hydrateDone;

      expect(cubit.state.supervisorPhone, repository.refreshPhone);
      expect(cubit.supervisorPhone, repository.refreshPhone);
    });
  });
}
