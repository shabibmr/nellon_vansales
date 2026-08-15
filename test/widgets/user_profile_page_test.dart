import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van_sales/data/services/hive_database_service.dart';
import 'package:van_sales/domain/models/salesperson.dart';
import 'package:van_sales/ui/core/cubit/salesperson_cubit.dart';
import 'package:van_sales/ui/features/auth/bloc/auth_bloc.dart';
import 'package:van_sales/ui/features/auth/logout.dart';
import 'package:van_sales/ui/features/profile/views/user_profile_page.dart';

class _FakeSalespersonCubit extends Cubit<Salesperson?>
    implements SalespersonCubit {
  _FakeSalespersonCubit([super.initial]);

  @override
  String? get locationId => state?.locationId;

  @override
  String? get name {
    final n = state?.name.trim();
    if (n == null || n.isEmpty) return null;
    return n;
  }

  @override
  String? get phone {
    final p = state?.phone?.trim();
    if (p == null || p.isEmpty) return null;
    return p;
  }

  @override
  void refresh(HiveDatabaseService db) {}
}

class _FakeAuthBloc extends Fake implements AuthBloc {
  final events = <AuthEvent>[];
  final _controller = StreamController<AuthState>.broadcast();

  @override
  AuthState get state => Unauthenticated();

  @override
  Stream<AuthState> get stream => _controller.stream;

  @override
  void add(AuthEvent event) => events.add(event);

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  const salesperson = Salesperson(
    id: 'sp_1',
    name: 'Test Agent',
    email: 'agent@example.com',
    phone: '+971500000000',
    locationName: 'SHINAD',
    cashAccountName: 'Cash in Hand',
    voucherPrefix: 'SH',
    status: 'active',
  );

  testWidgets('My Profile shows a Log out option', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SalespersonCubit>.value(
          value: _FakeSalespersonCubit(salesperson),
          child: const UserProfilePage(),
        ),
      ),
    );

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Test Agent'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Log out'), 200);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('Log out remains available when there is no active session', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SalespersonCubit>.value(
          value: _FakeSalespersonCubit(),
          child: const UserProfilePage(),
        ),
      ),
    );

    expect(find.text('No active session.'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('attemptLogout dispatches LogoutRequested when cash is closed', (
    tester,
  ) async {
    final authBloc = _FakeAuthBloc();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => attemptLogout(
                  context,
                  hasPendingCashClosing: false,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(authBloc.events.whereType<LogoutRequested>(), hasLength(1));
    expect(find.text('Cash Closing Required'), findsNothing);

    await authBloc.close();
  });

  testWidgets('attemptLogout blocks when cash closing is pending', (
    tester,
  ) async {
    final authBloc = _FakeAuthBloc();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => attemptLogout(
                  context,
                  hasPendingCashClosing: true,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(authBloc.events, isEmpty);
    expect(find.text('Cash Closing Required'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Cash Closing Required'), findsNothing);

    await authBloc.close();
  });
}
