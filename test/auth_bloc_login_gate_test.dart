import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/domain/models/phone_auth_event.dart';
import 'package:van_sales/domain/models/salesperson.dart';
import 'package:van_sales/domain/models/session_bind_result.dart';
import 'package:van_sales/domain/models/user.dart';
import 'package:van_sales/domain/repositories/auth_repository.dart';
import 'package:van_sales/domain/repositories/salesperson_repository.dart';
import 'package:van_sales/data/services/document_number_service.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/data/services/zoho_api_client.dart';
import 'package:van_sales/ui/features/auth/bloc/auth_bloc.dart';

class _FakeAuthRepository implements AuthRepository {
  User? _currentUser;
  int signOutCalls = 0;
  Exception? smsSignInError;
  bool acceptSmsCode = true;

  /// Emitted on [startPhoneVerification] (default: code sent successfully).
  PhoneAuthEvent? nextPhoneEvent = const PhoneCodeSent(
    verificationId: 'vid_test',
    resendToken: 42,
  );

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
    final event = nextPhoneEvent;
    if (event != null) {
      scheduleMicrotask(() {
        if (!controller.isClosed) {
          controller.add(event);
        }
      });
    }
    return controller.stream;
  }

  @override
  Future<User?> signInWithSmsCode(String verificationId, String smsCode) async {
    if (smsSignInError != null) throw smsSignInError!;
    if (!acceptSmsCode || smsCode == '000000') return null;
    _currentUser = const User(
      id: 'uid_1',
      name: 'From Firebase',
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
    _currentUser = const User(
      id: 'uid_auto',
      name: 'From Firebase Auto',
      email: '',
      phone: '+971542891246',
      role: 'agent',
    );
    return _currentUser;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _currentUser = null;
  }
}

class _FakeSalespersonRepository implements SalespersonRepository {
  SessionBindResult bindResult = SessionBindResult.failed(
    SessionBindFailure.notRegistered,
  );
  bool throwOnResolve = false;
  int clearCalls = 0;
  int bindCalls = 0;

  @override
  Future<SessionBindResult> verifyAndBindSession(String phone) async {
    bindCalls++;
    if (throwOnResolve) throw Exception('network');
    return bindResult;
  }

  @override
  Future<Salesperson?> resolveActiveSalesperson(String phone) async {
    final r = await verifyAndBindSession(phone);
    return r.salesperson;
  }

  @override
  List<Salesperson> getCachedSalespersons() => const [];

  @override
  Salesperson? get currentSalesperson => bindResult.salesperson;

  @override
  bool get isOrdersOnlyMode => false;

  @override
  Future<void> clearCurrentSalesperson() async {
    clearCalls++;
  }
}

/// Drives phone → OTP → authenticated (or failure) through [AuthBloc].
Future<void> _completeOtpLogin(AuthBloc bloc, {String code = '123456'}) async {
  bloc.add(const PhoneSubmitted('+971542891246'));
  await bloc.stream.firstWhere((s) => s is AuthCodeSent);
  bloc.add(OtpSubmitted(code));
}

class _FakeDocDb extends HiveDatabaseService {
  final Map<String, int> _counters = {};

  @override
  String? get voucherPrefix => 'SHB-';

  @override
  int? getDocCounter(String tag) => _counters[tag];

  @override
  Future<void> setDocCounter(String tag, int value) async {
    _counters[tag] = value;
  }
}

class _FakeZohoApi extends ZohoApiClient {
  _FakeZohoApi() : super(dbService: _FakeDocDb());
}

class _FakeDocNumberService extends DocumentNumberService {
  _FakeDocNumberService() : super(dbService: _FakeDocDb(), apiClient: _FakeZohoApi());

  @override
  Future<void> seedCounters() async {}
}

void main() {
  late _FakeAuthRepository auth;
  late _FakeSalespersonRepository salespersons;
  late AuthBloc bloc;

  final boundSalesperson = const Salesperson(
    id: 'sp_1',
    name: 'Zoho Agent',
    email: 'agent@nellon.com',
    phone: '+971542891246',
    locationId: '3331482000177581063',
    locationName: 'MANSOOR',
    voucherPrefix: 'MNS',
    cashAccountId: 'acc_cash',
  );

  setUp(() {
    auth = _FakeAuthRepository();
    salespersons = _FakeSalespersonRepository();
    bloc = AuthBloc(
      authRepository: auth,
      salespersonRepository: salespersons,
      documentNumberService: _FakeDocNumberService(),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('OTP login succeeds when Zoho profile bind succeeds', () async {
    salespersons.bindResult = SessionBindResult.success(boundSalesperson);

    final future = expectLater(
      bloc.stream,
      emitsThrough(
        isA<Authenticated>().having(
          (s) => s.user.name,
          'name',
          'Zoho Agent',
        ),
      ),
    );

    await _completeOtpLogin(bloc);
    await future;
    expect(auth.signOutCalls, 0);
    expect(salespersons.bindCalls, 1);
  });

  test(
    'OTP login fails and signs out when phone is not registered in Zoho',
    () async {
      salespersons.bindResult =
          SessionBindResult.failed(SessionBindFailure.notRegistered);

      final future = expectLater(
        bloc.stream,
        emitsThrough(
          isA<AuthFailure>().having(
            (s) => s.message,
            'message',
            'Not registered — contact admin.',
          ),
        ),
      );

      await _completeOtpLogin(bloc);
      await future;
      expect(auth.signOutCalls, 1);
      expect(salespersons.clearCalls, greaterThanOrEqualTo(1));
      expect(auth.currentUser, isNull);
    },
  );

  test('OTP login fails when profile is not fully mapped', () async {
    salespersons.bindResult =
        SessionBindResult.failed(SessionBindFailure.notFullyMapped);

    final future = expectLater(
      bloc.stream,
      emitsThrough(
        isA<AuthFailure>().having(
          (s) => s.message,
          'message',
          'Not fully mapped — contact admin.',
        ),
      ),
    );

    await _completeOtpLogin(bloc);
    await future;
    expect(auth.signOutCalls, 1);
  });

  test('OTP login fails when Zoho identity masters cannot be fetched', () async {
    salespersons.throwOnResolve = true;

    final future = expectLater(
      bloc.stream,
      emitsThrough(
        isA<AuthFailure>().having(
          (s) => s.message,
          'message',
          contains('Unable to verify with Zoho'),
        ),
      ),
    );

    await _completeOtpLogin(bloc);
    await future;
    expect(auth.signOutCalls, 1);
  });

  test('invalid phone number is rejected before OTP', () async {
    final future = expectLater(
      bloc.stream,
      emits(
        isA<AuthFailure>().having(
          (s) => s.message,
          'message',
          'Enter a valid mobile number in international format (e.g. +971501234567).',
        ),
      ),
    );

    bloc.add(const PhoneSubmitted('123'));
    await future;
    expect(salespersons.bindCalls, 0);
  });

  test('wrong OTP stays unauthenticated and does not bind', () async {
    salespersons.bindResult = SessionBindResult.success(boundSalesperson);
    auth.acceptSmsCode = false;

    final future = expectLater(
      bloc.stream,
      emitsThrough(
        isA<AuthFailure>().having(
          (s) => s.message,
          'message',
          'Incorrect code. Please try again.',
        ),
      ),
    );

    await _completeOtpLogin(bloc, code: '000000');
    await future;
    expect(salespersons.bindCalls, 0);
  });

  test('AppStarted forces logout for legacy email sessions (empty phone)',
      () async {
    auth._currentUser = const User(
      id: 'legacy',
      name: 'Old Email User',
      email: 'agent@nellon.com',
      phone: '',
      role: 'agent',
    );

    final future = expectLater(
      bloc.stream,
      emits(isA<Unauthenticated>()),
    );

    bloc.add(AppStarted());
    await future;
    expect(auth.signOutCalls, 1);
  });

  test('AppStarted rebinds an existing phone session', () async {
    auth._currentUser = const User(
      id: 'uid_1',
      name: 'From Firebase',
      email: '',
      phone: '+971542891246',
      role: 'agent',
    );
    salespersons.bindResult = SessionBindResult.success(boundSalesperson);

    final future = expectLater(
      bloc.stream,
      emits(
        isA<Authenticated>().having(
          (s) => s.user.name,
          'name',
          'Zoho Agent',
        ),
      ),
    );

    bloc.add(AppStarted());
    await future;
    expect(salespersons.bindCalls, 1);
  });

  test('OtpAborted returns to unauthenticated phone step', () async {
    salespersons.bindResult = SessionBindResult.success(boundSalesperson);

    bloc.add(const PhoneSubmitted('+971542891246'));
    await bloc.stream.firstWhere((s) => s is AuthCodeSent);

    final future = expectLater(
      bloc.stream,
      emits(isA<Unauthenticated>()),
    );
    bloc.add(OtpAborted());
    await future;
  });
}
