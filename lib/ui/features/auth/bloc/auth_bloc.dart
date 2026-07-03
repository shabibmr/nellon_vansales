import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/models/user.dart';
import '../../../../domain/repositories/auth_repository.dart';

// --- Events ---

/// Base class for all authentication events processed by [AuthBloc].
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// Triggered when the application first boots to verify if a cached user session exists.
class AppStarted extends AuthEvent {}

/// Fired when a user submits an email/password combination to log in.
class LoginRequested extends AuthEvent {
  /// The user's input email.
  final String email;

  /// The user's input password.
  final String password;

  /// Creates a [LoginRequested] event.
  const LoginRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
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

/// Authentication transaction actively running (e.g. validating password, logging out).
class AuthLoading extends AuthState {}

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

/// Authentication transaction failed (e.g. invalid credentials, network dropout).
class AuthFailure extends AuthState {
  /// Desctriptive error message.
  final String message;

  /// Creates an [AuthFailure] state.
  const AuthFailure(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

/// Business Logic Component managing user session states (Login, Sign-out, App Initialization).
///
/// Drives authentication workflows by mapping incoming [AuthEvent]s to appropriate [AuthState]s
/// using an underlying [AuthRepository] implementation.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  /// Instantiates a new [AuthBloc] with the specified repository.
  AuthBloc({required this._authRepository}) : super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  /// Verifies active session on start.
  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    final user = _authRepository.currentUser;
    if (user != null) {
      emit(Authenticated(user));
    } else {
      emit(Unauthenticated());
    }
  }

  /// Handles sign in credential validation and maps failures.
  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await _authRepository.signIn(event.email, event.password);
      if (user != null) {
        emit(Authenticated(user));
      } else {
        emit(const AuthFailure('Login failed: Invalid credentials'));
      }
    } catch (e) {
      emit(AuthFailure(e.toString().replaceAll('Exception: ', '')));
    }
  }

  /// Handles session termination.
  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    await _authRepository.signOut();
    emit(Unauthenticated());
  }
}
