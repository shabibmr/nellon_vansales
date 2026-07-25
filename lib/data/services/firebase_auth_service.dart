import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../domain/models/phone_auth_event.dart';
import '../../domain/models/user.dart';

/// Service interfacing directly with Firebase Authentication SDK.
///
/// Drives Phone OTP verification and translates Firebase user sessions to
/// standard [User] domain profiles.
class FirebaseAuthService {
  final fb.FirebaseAuth _firebaseAuth = fb.FirebaseAuth.instance;

  /// Stream of [User] updates that fires whenever authentication states change (logins/logouts).
  Stream<User?> get onAuthStateChanged {
    return _firebaseAuth.authStateChanges().map(_mapFirebaseUser);
  }

  /// Gets the currently authenticated user session. Returns null if unauthenticated.
  User? get currentUser {
    final user = _firebaseAuth.currentUser;
    return _mapFirebaseUser(user);
  }

  /// Starts OTP delivery for [e164Phone] (e.g. `+971542891246`).
  ///
  /// Bridges `verifyPhoneNumber`'s four callbacks into a single stream so a
  /// caller can `await for` (or subscribe to) [PhoneAuthEvent]s. Pass
  /// [forceResendingToken] (from a prior [PhoneCodeSent]) to resend without
  /// re-running device attestation.
  Stream<PhoneAuthEvent> startPhoneVerification(
    String e164Phone, {
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final controller = StreamController<PhoneAuthEvent>();

    _firebaseAuth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      timeout: timeout,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) {
        controller.add(PhoneAutoVerified(credential));
      },
      verificationFailed: (exception) {
        controller.add(PhoneVerificationFailed(exception));
        controller.close();
      },
      codeSent: (verificationId, resendToken) {
        controller.add(
          PhoneCodeSent(verificationId: verificationId, resendToken: resendToken),
        );
      },
      codeAutoRetrievalTimeout: (verificationId) {
        controller.add(PhoneCodeAutoRetrievalTimeout(verificationId));
      },
    );

    return controller.stream;
  }

  /// Completes sign-in with a manually entered OTP.
  ///
  /// Throws [fb.FirebaseAuthException] (e.g. `invalid-verification-code`,
  /// `session-expired`).
  Future<User?> signInWithSmsCode(String verificationId, String smsCode) async {
    final credential = fb.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return signInWithPhoneCredential(credential);
  }

  /// Completes sign-in with an auto-retrieved or manually built credential.
  Future<User?> signInWithPhoneCredential(
    fb.PhoneAuthCredential credential,
  ) async {
    final userCredential = await _firebaseAuth.signInWithCredential(
      credential,
    );
    return _mapFirebaseUser(userCredential.user);
  }

  /// Logs out of Firebase and kills active sessions.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Maps standard Firebase user entities into the custom domain [User] profile.
  User? _mapFirebaseUser(fb.User? user) {
    if (user == null) return null;

    return User(
      id: user.uid,
      name: user.displayName ?? user.phoneNumber ?? 'Van Sales Agent',
      email: user.email ?? '',
      phone: user.phoneNumber ?? '',
      role: 'agent',
      // The active route ID and assigned warehouse are loaded from local Hive master storage
      activeRouteId: null,
      assignedVanWarehouseId: null,
    );
  }
}
