import 'package:van_sales/domain/models/user.dart';
import 'package:van_sales/ui/features/licensing/cubit/license_cubit.dart';
import 'test/license_cubit_test.dart';

void main() async {
  print('--- START DEBUGGING LICENSE CUBIT ---');
  final localService = FakeLocalStorageService();
  final deviceService = FakeDeviceInfoService();
  final licenseService = FakeLicenseService();

  final cubit = LicenseCubit(
    licenseService: licenseService,
    localStorageService: localService,
    deviceInfoService: deviceService,
  );

  cubit.stream.listen((state) {
    print('EMITTED STATE: $state');
  });

  const testUser = User(
    id: 'user_123',
    name: 'John Agent',
    email: 'john@sales.com',
    role: 'agent',
  );

  print('Calling checkLicense...');
  await cubit.checkLicense(testUser);
  print('checkLicense finished.');

  await Future.delayed(const Duration(milliseconds: 100));
  print('Cubit state: ${cubit.state}');
  print('--- END DEBUGGING ---');
  cubit.close();
}
