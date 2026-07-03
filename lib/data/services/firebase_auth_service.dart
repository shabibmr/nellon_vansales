import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../domain/models/user.dart';

/// Service interfacing directly with Firebase Authentication SDK.
///
/// Handles logging users in, managing session listeners, and translating Firebase user models
/// to standard [User] domain profiles.
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

  /// Authenticates credentials with Firebase Authentication.
  ///
  /// Throws standard Firebase auth exceptions if validation or network connection fails.
  Future<User?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _mapFirebaseUser(credential.user);
  }

  /// Logs out of Firebase and kills active sessions.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Maps standard Firebase user entities into the custom domain [User] profile.
  ///
  /// In a production environment, additional fields like dynamic agent authorization roles
  /// and van warehouse configurations are retrieved via custom Firebase claims or Firestore records.
  User? _mapFirebaseUser(fb.User? user) {
    if (user == null) return null;

    return User(
      id: user.uid,
      name: user.displayName ?? user.email?.split('@')[0] ?? 'Van Sales Agent',
      email: user.email ?? '',
      role: 'agent',
      // The active route ID and assigned warehouse are loaded from local Hive master storage
      activeRouteId: null,
      assignedVanWarehouseId: null,
    );
  }
}
