import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../domain/models/user.dart';

class FirebaseAuthService {
  final fb.FirebaseAuth _firebaseAuth = fb.FirebaseAuth.instance;

  // Stream of User Auth state
  Stream<User?> get onAuthStateChanged {
    return _firebaseAuth.authStateChanges().map(_mapFirebaseUser);
  }

  // Get current user
  User? get currentUser {
    final user = _firebaseAuth.currentUser;
    return _mapFirebaseUser(user);
  }

  // Sign in with email and password
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _mapFirebaseUser(credential.user);
  }

  // Sign out
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  // Helper mapper: Firebase User -> Domain User
  User? _mapFirebaseUser(fb.User? user) {
    if (user == null) return null;
    
    // In a real-world scenario, you can fetch metadata (role, assigned warehouse) 
    // from Firestore/Realtime DB or custom claims.
    // For this direct Zoho app integration, we map details, defaulting to a standard Agent profile.
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
