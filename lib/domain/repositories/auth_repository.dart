import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../models/phone_auth_event.dart';
import '../models/user.dart';

/// Abstract contract for authentication data flow.
///
/// Coordinates Phone OTP verification and session streams.
abstract class AuthRepository {
  /// Stream that fires when the user's authentication state shifts (login/logout).
  Stream<User?> get onAuthStateChanged;

  /// Retrieves the currently cached profile session. Returns null if unauthenticated.
  User? get currentUser;

  /// Starts OTP delivery for [e164Phone]. See [FirebaseAuthService.startPhoneVerification].
  Stream<PhoneAuthEvent> startPhoneVerification(
    String e164Phone, {
    int? forceResendingToken,
  });

  /// Completes sign-in with a manually entered OTP.
  Future<User?> signInWithSmsCode(String verificationId, String smsCode);

  /// Completes sign-in with an auto-retrieved credential.
  Future<User?> signInWithPhoneCredential(fb.PhoneAuthCredential credential);

  /// Destroys the active session and clears the local authenticated cache state.
  Future<void> signOut();
}
