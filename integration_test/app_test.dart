import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:van_sales/app.dart';
import 'package:van_sales/ui/features/auth/views/login_page.dart';
import 'package:van_sales/domain/models/phone_auth_event.dart';
import 'package:van_sales/domain/repositories/auth_repository.dart';
import 'package:van_sales/domain/repositories/sync_repository.dart';
import 'package:van_sales/domain/models/user.dart';
import 'package:van_sales/data/models/sync_queue_item.dart';
import 'package:van_sales/data/services/sync_worker.dart';
import 'package:get_it/get_it.dart';

// Fake implementations to isolate E2E UI rendering from disk/network IO
class FakeAuthRepository implements AuthRepository {
  User? _currentUser;

  @override
  Stream<User?> get onAuthStateChanged => Stream.value(_currentUser);

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<PhoneAuthEvent> startPhoneVerification(
    String e164Phone, {
    int? forceResendingToken,
  }) {
    final controller = StreamController<PhoneAuthEvent>();
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          const PhoneCodeSent(verificationId: 'vid_mock', resendToken: 1),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<User?> signInWithSmsCode(String verificationId, String smsCode) async {
    _currentUser = const User(
      id: 'usr_mock_123',
      name: 'Agent Nellon',
      email: '',
      phone: '+971542891246',
      role: 'agent',
    );
    return _currentUser;
  }

  @override
  Future<User?> signInWithPhoneCredential(
    fb.PhoneAuthCredential credential,
  ) async {
    return signInWithSmsCode('auto', '000000');
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class FakeSyncRepository implements SyncRepository {
  @override
  Stream<String> get syncStatusStream => const Stream.empty();

  @override
  Stream<int> get syncCountStream => const Stream.empty();

  @override
  bool get isSyncing => false;

  @override
  List<SyncQueueItem> getSyncQueue() => [];

  @override
  Future<void> triggerSync({bool forceRetryAll = false}) async {}

  @override
  Future<void> clearFailedSyncItems() async {}

  @override
  Future<void> refreshMasterData() async {}

  @override
  Future<void> syncMaster(MasterType type) async {}

  @override
  bool hasCoreMasters() => true;

  @override
  int getMasterRecordCount(MasterType type) => 0;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Van Sales End-to-End UI Integration Test', () {
    setUpAll(() {
      final sl = GetIt.instance;
      // Register Fakes inside Service Locator container prior to application loading
      sl.registerLazySingleton<AuthRepository>(() => FakeAuthRepository());
      sl.registerLazySingleton<SyncRepository>(() => FakeSyncRepository());
    });

    testWidgets(
      'Verify phone OTP login surface loads (phone step)',
      (WidgetTester tester) async {
        // 1. Boot the application widget tree
        await tester.pumpWidget(const VanSalesApp());
        await tester.pumpAndSettle();

        // 2. Expect LoginPage with phone OTP entry (not email/password)
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text('SEND CODE'), findsOneWidget);
        expect(find.byType(TextFormField), findsOneWidget);
        expect(find.textContaining('Mobile Number'), findsOneWidget);
      },
    );
  });
}
