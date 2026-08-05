import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/ui/features/auth/bloc/auth_bloc.dart';
import 'package:van_sales/ui/features/auth/views/login_page.dart';

class _FakeAuthBloc extends Fake implements AuthBloc {
  final _controller = StreamController<AuthState>.broadcast();
  AuthState _state;

  _FakeAuthBloc(this._state);

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _controller.stream;

  void emitState(AuthState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  void add(AuthEvent event) {}
}

void main() {
  testWidgets('LoginPage shows phone field and OTP step after AuthCodeSent', (
    tester,
  ) async {
    final authBloc = _FakeAuthBloc(Unauthenticated());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: const LoginPage(),
        ),
      ),
    );

    expect(find.byType(TextFormField), findsOneWidget);

    authBloc.emitState(
      const AuthCodeSent(
        phone: '+15551234567',
        verificationId: 'vid',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);
    expect(find.textContaining('VERIFY'), findsWidgets);

    await authBloc.close();
  });
}
