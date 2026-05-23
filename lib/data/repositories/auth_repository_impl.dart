import '../../domain/models/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../services/firebase_auth_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuthService _authService;

  AuthRepositoryImpl({required FirebaseAuthService this._authService});

  @override
  Stream<User?> get onAuthStateChanged => _authService.onAuthStateChanged;

  @override
  User? get currentUser => _authService.currentUser;

  @override
  Future<User?> signIn(String email, String password) {
    return _authService.signInWithEmailAndPassword(email, password);
  }

  @override
  Future<void> signOut() {
    return _authService.signOut();
  }
}
