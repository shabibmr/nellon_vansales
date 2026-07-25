import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../../../domain/models/phone_auth_event.dart';
import '../../../../domain/models/session_bind_result.dart';
import '../../../../domain/models/user.dart';
import '../../../../domain/repositories/auth_repository.dart';
import '../../../../domain/repositories/salesperson_repository.dart';
import '../../../../domain/utils/phone_normalizer.dart';
import '../../../../data/services/document_number_service.dart';
import '../../../../data/services/injection.dart';

// --- Events ---

/// Base class for all authentication events processed by [AuthBloc].
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// Triggered when the application first boots to verify if a cached user session exists.
class AppStarted extends AuthEvent {}

/// Fired when a user submits a phone number to start OTP verification.
class PhoneSubmitted extends AuthEvent {
  /// Raw phone as typed (local `05…` or E.164 accepted).
  final String rawPhone;

  /// Creates a [PhoneSubmitted] event.
  const PhoneSubmitted(this.rawPhone);

  @override
  List<Object?> get props => [rawPhone];
}

/// Fired when the user submits the received OTP code.
class OtpSubmitted extends AuthEvent {
  /// The 6-digit code entered by the user.
  final String smsCode;

  /// Creates an [OtpSubmitted] event.
  const OtpSubmitted(this.smsCode);

  @override
  List<Object?> get props => [smsCode];
}

/// Requests the OTP be re-sent to the pending phone number.
class OtpResendRequested extends AuthEvent {}

/// User backed out of OTP entry to re-enter their phone number.
class OtpAborted extends AuthEvent {}

/// Internal: forwards a [PhoneAuthEvent] from the Firebase verification stream.
class PhoneAuthEventReceived extends AuthEvent {
  final PhoneAuthEvent event;

  const PhoneAuthEventReceived(this.event);

  @override
  List<Object?> get props => [event];
}

/// Fired when the user requests to sign out and end the active session.
class LogoutRequested extends AuthEvent {}

// --- States ---

/// Base class for all authentication states broadcast by [AuthBloc].
abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// The initial state when BLoC is spawned.
class AuthInitial extends AuthState {}

/// Authentication transaction actively running (e.g. requesting OTP, logging out).
class AuthLoading extends AuthState {}

/// OTP was dispatched to [phone]; UI shows the code-entry step.
class AuthCodeSent extends AuthState {
  /// E.164 phone the code was sent to.
  final String phone;

  /// Verification id needed to complete sign-in.
  final String verificationId;

  /// Resend token for re-sending without repeating device attestation.
  final int? resendToken;

  /// Whether Android auto-retrieval already timed out (enables immediate resend).
  final bool autoRetrievalTimedOut;

  /// Creates an [AuthCodeSent] state.
  const AuthCodeSent({
    required this.phone,
    required this.verificationId,
    this.resendToken,
    this.autoRetrievalTimedOut = false,
  });

  @override
  List<Object?> get props => [
    phone,
    verificationId,
    resendToken,
    autoRetrievalTimedOut,
  ];
}

/// OTP is being verified (manual entry or auto-retrieval); code entry disabled.
class AuthVerifyingOtp extends AuthState {
  /// E.164 phone being verified.
  final String phone;

  /// Creates an [AuthVerifyingOtp] state.
  const AuthVerifyingOtp(this.phone);

  @override
  List<Object?> get props => [phone];
}

/// Session verified; maps the active [User] object.
class Authenticated extends AuthState {
  /// The currently authenticated user profile.
  final User user;

  /// Creates an [Authenticated] state.
  const Authenticated(this.user);

  @override
  List<Object?> get props => [user];
}

/// No active session cached. Routes user to login view.
class Unauthenticated extends AuthState {}

/// Authentication transaction failed (e.g. invalid code, network dropout).
class AuthFailure extends AuthState {
  /// Descriptive error message.
  final String message;

  /// Creates an [AuthFailure] state.
  const AuthFailure(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

/// Business Logic Component managing user session states (Phone OTP, Sign-out).
///
/// Flow: Firebase Phone OTP verification first → on success, Zoho
/// `cm_salesperson_profile` lookup → bind session.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SalespersonRepository _salespersonRepository;

  static const _msgNotRegistered = 'Not registered — contact admin.';
  static const _msgDisabled = 'Login disabled — contact admin.';
  static const _msgNotFullyMapped = 'Not fully mapped — contact admin.';
  static const _msgNetwork =
      'Unable to verify with Zoho. Check network and retry.';
  static const _msgInvalidPhone =
      'Enter a valid mobile number in international format (e.g. +971501234567).';
  static const _msgInvalidCode = 'Incorrect code. Please try again.';

  String? _pendingPhone;
  String? _verificationId;
  int? _resendToken;
  StreamSubscription<PhoneAuthEvent>? _phoneSub;

  /// Instantiates a new [AuthBloc] with the specified repositories.
  AuthBloc({
    required AuthRepository authRepository,
    required SalespersonRepository salespersonRepository,
  })  : _authRepository = authRepository,
        _salespersonRepository = salespersonRepository,
        super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<PhoneSubmitted>(_onPhoneSubmitted);
    on<OtpSubmitted>(_onOtpSubmitted);
    on<OtpResendRequested>(_onOtpResendRequested);
    on<OtpAborted>(_onOtpAborted);
    on<PhoneAuthEventReceived>(_onPhoneAuthEventReceived);
    on<LogoutRequested>(_onLogoutRequested);
  }

  String _messageForBindFailure(SessionBindFailure failure) {
    switch (failure) {
      case SessionBindFailure.notRegistered:
        return _msgNotRegistered;
      case SessionBindFailure.disabled:
        return _msgDisabled;
      case SessionBindFailure.notFullyMapped:
        return _msgNotFullyMapped;
      case SessionBindFailure.network:
        return _msgNetwork;
    }
  }

  /// Applies Zoho display name onto the Firebase [user] profile.
  User _userWithSalespersonName(User user, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return user;
    return user.copyWith(name: trimmed);
  }

  Future<void> _tearDownSession() async {
    try {
      await _authRepository.signOut();
    } catch (_) {}
    try {
      await _salespersonRepository.clearCurrentSalesperson();
    } catch (_) {}
  }

  void _resetPendingOtpState() {
    _phoneSub?.cancel();
    _phoneSub = null;
    _pendingPhone = null;
    _verificationId = null;
    _resendToken = null;
  }

  /// Binds Zoho session for [user]; returns Authenticated user or emits failure.
  Future<User?> _bindAfterFirebase(User user, Emitter<AuthState> emit) async {
    SessionBindResult result;
    try {
      result = await _salespersonRepository
          .verifyAndBindSession(user.phone)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      await _tearDownSession();
      emit(const AuthFailure(_msgNetwork));
      return null;
    }

    if (!result.isSuccess || result.salesperson == null) {
      await _tearDownSession();
      emit(
        AuthFailure(
          _messageForBindFailure(
            result.failure ?? SessionBindFailure.network,
          ),
        ),
      );
      return null;
    }

    unawaited(_seedNumberingCounters());
    return _userWithSalespersonName(user, result.salesperson!.name);
  }

  Future<void> _seedNumberingCounters() async {
    try {
      await sl<DocumentNumberService>().seedCounters();
    } catch (_) {
      // Numbering seed failures never block the session; nextNumber()
      // falls back to persisted counters.
    }
  }

  /// Verifies active session on start.
  ///
  /// Returning sessions re-check Zoho when online. If the mapping is gone (or
  /// the network call fails), the cached Firebase session is still accepted so
  /// offline reopen is not blocked — authorization is enforced strictly on
  /// interactive [PhoneSubmitted] / [OtpSubmitted].
  ///
  /// A Firebase session left over from the old email-login flow has an empty
  /// [User.phone] and cannot be bound — it is signed out to force OTP re-login.
  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    final user = _authRepository.currentUser;
    if (user == null) {
      emit(Unauthenticated());
      return;
    }

    if (user.phone.isEmpty) {
      await _tearDownSession();
      emit(Unauthenticated());
      return;
    }

    try {
      final result = await _salespersonRepository
          .verifyAndBindSession(user.phone)
          .timeout(const Duration(seconds: 15));
      if (result.isSuccess && result.salesperson != null) {
        unawaited(_seedNumberingCounters());
        emit(
          Authenticated(
            _userWithSalespersonName(user, result.salesperson!.name),
          ),
        );
        return;
      }
    } catch (_) {
      // Offline reopen: keep Firebase session.
    }
    emit(Authenticated(user));
  }

  Future<void> _onPhoneSubmitted(
    PhoneSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final normalized = normalizePhone(event.rawPhone.trim());
    if (!isValidE164(normalized)) {
      emit(const AuthFailure(_msgInvalidPhone));
      return;
    }

    _resetPendingOtpState();
    _pendingPhone = normalized;
    emit(AuthLoading());

    await _subscribeToPhoneVerification(normalized);
  }

  Future<void> _subscribeToPhoneVerification(
    String phone, {
    int? forceResendingToken,
  }) async {
    _phoneSub = _authRepository
        .startPhoneVerification(phone, forceResendingToken: forceResendingToken)
        .listen((event) => add(PhoneAuthEventReceived(event)));
  }

  Future<void> _onPhoneAuthEventReceived(
    PhoneAuthEventReceived event,
    Emitter<AuthState> emit,
  ) async {
    final phoneEvent = event.event;
    switch (phoneEvent) {
      case PhoneCodeSent():
        _verificationId = phoneEvent.verificationId;
        _resendToken = phoneEvent.resendToken;
        emit(
          AuthCodeSent(
            phone: _pendingPhone!,
            verificationId: phoneEvent.verificationId,
            resendToken: phoneEvent.resendToken,
          ),
        );
      case PhoneAutoVerified():
        emit(AuthVerifyingOtp(_pendingPhone ?? ''));
        await _completeSignIn(
          () => _authRepository.signInWithPhoneCredential(
            phoneEvent.credential,
          ),
          emit,
        );
      case PhoneVerificationFailed():
        _resetPendingOtpState();
        emit(AuthFailure(_friendlyPhoneAuthMessage(phoneEvent.exception)));
      case PhoneCodeAutoRetrievalTimeout():
        _verificationId = phoneEvent.verificationId;
        emit(
          AuthCodeSent(
            phone: _pendingPhone ?? '',
            verificationId: phoneEvent.verificationId,
            resendToken: _resendToken,
            autoRetrievalTimedOut: true,
          ),
        );
    }
  }

  Future<void> _onOtpSubmitted(
    OtpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final verificationId = _verificationId;
    final phone = _pendingPhone;
    if (verificationId == null || phone == null) {
      emit(const AuthFailure(_msgInvalidCode));
      return;
    }

    emit(AuthVerifyingOtp(phone));
    await _completeSignIn(
      () => _authRepository.signInWithSmsCode(verificationId, event.smsCode),
      emit,
    );
  }

  Future<void> _completeSignIn(
    Future<User?> Function() signIn,
    Emitter<AuthState> emit,
  ) async {
    try {
      final user = await signIn();
      if (user == null) {
        emit(const AuthFailure(_msgInvalidCode));
        return;
      }
      final bound = await _bindAfterFirebase(user, emit);
      if (bound != null) {
        _resetPendingOtpState();
        emit(Authenticated(bound));
      }
    } on fb.FirebaseAuthException catch (e) {
      emit(AuthFailure(_friendlyPhoneAuthMessage(e)));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onOtpResendRequested(
    OtpResendRequested event,
    Emitter<AuthState> emit,
  ) async {
    final phone = _pendingPhone;
    if (phone == null) return;
    await _subscribeToPhoneVerification(
      phone,
      forceResendingToken: _resendToken,
    );
  }

  Future<void> _onOtpAborted(
    OtpAborted event,
    Emitter<AuthState> emit,
  ) async {
    _resetPendingOtpState();
    emit(Unauthenticated());
  }

  String _friendlyPhoneAuthMessage(fb.FirebaseAuthException e) {
    switch (e.code.toLowerCase()) {
      case 'invalid-phone-number':
        return _msgInvalidPhone;
      case 'invalid-verification-code':
      case 'session-expired':
        return _msgInvalidCode;
      case 'too-many-requests':
      case 'quota-exceeded':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and retry.';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'Device verification failed — contact support.';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : _msgInvalidCode;
    }
  }

  /// Handles session termination.
  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    _resetPendingOtpState();
    await _authRepository.signOut();
    try {
      await _salespersonRepository.clearCurrentSalesperson();
    } catch (_) {
      // Session teardown should still complete if local clear fails.
    }
    emit(Unauthenticated());
  }

  @override
  Future<void> close() {
    _phoneSub?.cancel();
    return super.close();
  }
}
