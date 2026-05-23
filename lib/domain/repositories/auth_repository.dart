import '../models/user.dart';

abstract class AuthRepository {
  Stream<User?> get onAuthStateChanged;
  User? get currentUser;
  Future<User?> signIn(String email, String password);
  Future<void> signOut();
}
