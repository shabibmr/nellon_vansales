import '../models/user.dart';

/// Abstract contract for authentication data flow.
///
/// Coordinates credential validation, user profile mapping, and active session streams.
abstract class AuthRepository {
  /// Stream that fires when the user's authentication state shifts (login/logout).
  Stream<User?> get onAuthStateChanged;

  /// Retrieves the currently cached profile session. Returns null if unauthenticated.
  User? get currentUser;

  /// Validates credentials with the identity service, logs the user in, and maps profile.
  Future<User?> signIn(String email, String password);

  /// Destroys the active session and clears the local authenticated cache state.
  Future<void> signOut();
}
