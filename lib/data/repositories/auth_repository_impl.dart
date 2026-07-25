import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../domain/models/phone_auth_event.dart';
import '../../domain/models/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../services/firebase_auth_service.dart';

/// Concrete implementation of [AuthRepository] using a Firebase service provider.
///
/// Coordinates direct interaction with [FirebaseAuthService] for Phone OTP
/// authentication and user session mapping.
class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuthService _authService;

  /// Creates a new [AuthRepositoryImpl] requiring a [FirebaseAuthService].
  AuthRepositoryImpl({required FirebaseAuthService authService})
      : _authService = authService;

  @override
  Stream<User?> get onAuthStateChanged => _authService.onAuthStateChanged;

  @override
  User? get currentUser => _authService.currentUser;

  @override
  Stream<PhoneAuthEvent> startPhoneVerification(
    String e164Phone, {
    int? forceResendingToken,
  }) {
    return _authService.startPhoneVerification(
      e164Phone,
      forceResendingToken: forceResendingToken,
    );
  }

  @override
  Future<User?> signInWithSmsCode(String verificationId, String smsCode) {
    return _authService.signInWithSmsCode(verificationId, smsCode);
  }

  @override
  Future<User?> signInWithPhoneCredential(fb.PhoneAuthCredential credential) {
    return _authService.signInWithPhoneCredential(credential);
  }

  @override
  Future<void> signOut() {
    return _authService.signOut();
  }
}
