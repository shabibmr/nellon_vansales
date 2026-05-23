import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'data/services/injection.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/theme/theme_cubit.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/sync_repository.dart';
import 'domain/repositories/sales_repository.dart';
import 'ui/features/auth/bloc/auth_bloc.dart';
import 'ui/features/sync/bloc/sync_bloc.dart';
import 'ui/features/route/bloc/route_bloc.dart';
import 'ui/features/sales_invoice/bloc/sales_invoice_bloc.dart';
import 'ui/features/auth/views/login_page.dart';
import 'ui/features/route/views/route_page.dart';
import 'ui/features/dashboard/views/dashboard_page.dart';
import 'ui/features/sync/views/masters_sync_page.dart';

class VanSalesApp extends StatelessWidget {
  const VanSalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>(
          create: (context) => sl<AuthRepository>(),
        ),
        RepositoryProvider<SyncRepository>(
          create: (context) => sl<SyncRepository>(),
        ),
        RepositoryProvider<SalesRepository>(
          create: (context) => sl<SalesRepository>(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(
            create: (context) => ThemeCubit(),
          ),
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepository>(),
            )..add(AppStarted()),
          ),
          BlocProvider<SyncBloc>(
            create: (context) => SyncBloc(
              syncRepository: context.read<SyncRepository>(),
            )..add(SyncStarted()),
          ),
          BlocProvider<RouteBloc>(
            create: (context) => RouteBloc(
              salesRepository: context.read<SalesRepository>(),
            )..add(LoadRoutes()),
          ),
          BlocProvider<SalesInvoiceBloc>(
            create: (context) => SalesInvoiceBloc(
              salesRepository: context.read<SalesRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return MaterialApp(
              title: 'Van Sales Pro',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              home: const SessionGateway(),
            );
          },
        ),
      ),
    );
  }
}

class SessionGateway extends StatelessWidget {
  const SessionGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        if (authState is Authenticated) {
          return BlocBuilder<RouteBloc, RouteState>(
            builder: (context, routeState) {
              if (routeState.isLoading) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
                  ),
                );
              }
              final hasMasters = context.read<SyncRepository>().hasCoreMasters();
              if (!hasMasters) {
                return const MastersSyncPage();
              }
              if (routeState.activeRouteId == null || routeState.activeRouteId!.isEmpty) {
                return const RouteSelectionPage();
              }
              return const DashboardPage();
            },
          );
        } else if (authState is AuthLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
            ),
          );
        }
        return const LoginPage();
      },
    );
  }
}
