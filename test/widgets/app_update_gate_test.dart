import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/app_update_service.dart';
import 'package:van_sales/domain/models/app_update_info.dart';
import 'package:van_sales/ui/features/app_update/cubit/app_update_cubit.dart';
import 'package:van_sales/ui/features/app_update/views/app_update_force_screen.dart';
import 'package:van_sales/ui/features/app_update/views/app_update_gate.dart';

const _sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

AppUpdateInfo _info({required bool force, String notes = 'Notes'}) {
  return AppUpdateInfo(
    latestBuildNumber: 3,
    latestVersionName: '1.0.2',
    apkUrl: 'https://vps.example.com/app.apk',
    sha256: _sha,
    forceUpdate: force,
    releaseNotes: notes,
    currentBuildNumber: 1,
    currentVersionName: '1.0.0',
    isUpdateAvailable: true,
  );
}

class MockAppUpdateService extends AppUpdateService {
  AppUpdateInfo? mockUpdateInfo;
  final StreamController<OtaEvent> _otaController =
      StreamController<OtaEvent>.broadcast();
  final StreamController<AppUpdateInfo?> watchController =
      StreamController<AppUpdateInfo?>.broadcast();

  @override
  Future<AppUpdateInfo?> checkForUpdate() async => mockUpdateInfo;

  @override
  Stream<AppUpdateInfo?> watchAppVersion() => watchController.stream;

  @override
  Stream<OtaEvent> downloadAndInstallApk(String apkUrl, {required String sha256}) {
    return _otaController.stream;
  }

  void emitOtaEvent(OtaEvent event) => _otaController.add(event);

  void dispose() {
    _otaController.close();
    watchController.close();
  }
}

Future<void> _pumpGate(
  WidgetTester tester, {
  required AppUpdateCubit cubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<AppUpdateCubit>.value(
        value: cubit,
        child: const AppUpdateGate(
          child: Scaffold(body: Text('CHILD_CONTENT')),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  late MockAppUpdateService service;
  late AppUpdateCubit cubit;

  setUp(() {
    service = MockAppUpdateService();
    cubit = AppUpdateCubit(updateService: service);
  });

  tearDown(() async {
    await cubit.close();
    service.dispose();
  });

  testWidgets('force update replaces the child with the blocking screen', (
    tester,
  ) async {
    service.mockUpdateInfo = _info(force: true);

    await _pumpGate(tester, cubit: cubit);

    expect(find.text('CHILD_CONTENT'), findsNothing);
    expect(find.byType(AppUpdateForceScreen), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.text('v1.0.0 ➔ v1.0.2'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('optional update keeps the child and shows a Later button', (
    tester,
  ) async {
    service.mockUpdateInfo = _info(force: false);

    await _pumpGate(tester, cubit: cubit);

    expect(find.text('CHILD_CONTENT'), findsOneWidget);
    expect(find.byType(AppUpdateForceScreen), findsNothing);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Later'), findsNothing);
    expect(find.text('CHILD_CONTENT'), findsOneWidget);
  });

  testWidgets('downloading hides Later and shows progress text', (tester) async {
    service.mockUpdateInfo = _info(force: false);

    await _pumpGate(tester, cubit: cubit);
    expect(find.text('Update Now'), findsOneWidget);

    await tester.tap(find.text('Update Now'));
    await tester.pump();

    service.emitOtaEvent(const OtaEvent(OtaStatus.downloading, '45'));
    await tester.pump();

    expect(find.text('Downloading update: 45%'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
    expect(find.text('Update Now'), findsNothing);
  });
}
