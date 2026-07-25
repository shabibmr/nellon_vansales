import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Outcome events surfaced from `FirebaseAuth.verifyPhoneNumber` callbacks.
sealed class PhoneAuthEvent {
  const PhoneAuthEvent();
}

/// SMS was dispatched; [verificationId] is required to complete sign-in.
/// [resendToken] enables re-sending without re-triggering reCAPTCHA/Play
/// Integrity checks.
class PhoneCodeSent extends PhoneAuthEvent {
  final String verificationId;
  final int? resendToken;

  const PhoneCodeSent({required this.verificationId, this.resendToken});
}

/// Android auto-retrieval / instant verification completed without manual
/// OTP entry.
class PhoneAutoVerified extends PhoneAuthEvent {
  final fb.PhoneAuthCredential credential;

  const PhoneAutoVerified(this.credential);
}

/// Verification could not proceed (invalid number, quota, device attestation).
class PhoneVerificationFailed extends PhoneAuthEvent {
  final fb.FirebaseAuthException exception;

  const PhoneVerificationFailed(this.exception);
}

/// The auto-retrieval window elapsed; manual OTP entry is still valid using
/// the same [verificationId].
class PhoneCodeAutoRetrievalTimeout extends PhoneAuthEvent {
  final String verificationId;

  const PhoneCodeAutoRetrievalTimeout(this.verificationId);
}
