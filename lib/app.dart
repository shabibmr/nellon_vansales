// \file app.dart
// \brief Main application widget setting up providers, themes, and navigation routing gateways.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'data/services/injection.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/theme/theme_cubit.dart';
import 'ui/core/widgets/animated_glow_background.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/sync_repository.dart';
import 'domain/repositories/sales_repository.dart';
import 'ui/features/auth/bloc/auth_bloc.dart';
import 'ui/features/sync/bloc/sync_bloc.dart';
import 'ui/features/route/bloc/route_bloc.dart';
import 'ui/features/sales_invoice/bloc/sales_invoice_bloc.dart';
import 'ui/features/sales_order/bloc/sales_order_bloc.dart';
import 'ui/features/expenses/bloc/expense_bloc.dart';
import 'ui/features/receipts/bloc/receipt_bloc.dart';
import 'ui/features/sales_return/bloc/sales_return_bloc.dart';
import 'ui/features/ledger/bloc/customer_ledger_bloc.dart';
import 'ui/core/cubit/organization_cubit.dart';
import 'data/services/hive_database_service.dart';
import 'data/services/zoho_api_client.dart';
import 'ui/features/auth/views/login_page.dart';
import 'ui/features/route/views/route_page.dart';
import 'ui/features/dashboard/views/dashboard_page.dart';
import 'ui/features/sync/views/masters_sync_page.dart';
import 'data/services/local_storage_service.dart';
import 'data/services/device_info_service.dart';
import 'data/services/license_service.dart';
import 'ui/features/licensing/cubit/license_cubit.dart';
import 'ui/features/licensing/cubit/server_config_cubit.dart';
import 'ui/features/licensing/views/license_gate.dart';
import 'data/services/voucher_pdf_service.dart';
import 'ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart';

/// The root widget of the Van Sales Pro application.
///
/// Sets up:
/// 1. Global repositories via [MultiRepositoryProvider] injected through dependency injection ([sl]).
/// 2. Core application BLoCs via [MultiBlocProvider] for authentication, sync management, routing, and sales.
/// 3. Visual theme support (light, dark, dynamic) linked to [ThemeCubit].
/// 4. Home destination pointing to the [SessionGateway] to branch based on auth and setup state.
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
          BlocProvider<ThemeCubit>(create: (context) => ThemeCubit()),
          BlocProvider<OrganizationCubit>(
            create: (context) => OrganizationCubit(sl<HiveDatabaseService>()),
          ),
          BlocProvider<AuthBloc>(
            create: (context) =>
                AuthBloc(authRepository: context.read<AuthRepository>())
                  ..add(AppStarted()),
          ),
          BlocProvider<SyncBloc>(
            create: (context) =>
                SyncBloc(syncRepository: context.read<SyncRepository>())
                  ..add(SyncStarted()),
          ),
          BlocProvider<RouteBloc>(
            create: (context) =>
                RouteBloc(salesRepository: context.read<SalesRepository>())
                  ..add(LoadRoutes()),
          ),
          BlocProvider<SalesInvoiceBloc>(
            create: (context) => SalesInvoiceBloc(
              salesRepository: context.read<SalesRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
          BlocProvider<SalesOrderBloc>(
            create: (context) => SalesOrderBloc(
              salesRepository: context.read<SalesRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
          BlocProvider<ExpenseBloc>(
            create: (context) => ExpenseBloc(
              salesRepository: context.read<SalesRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
          BlocProvider<ReceiptBloc>(
            create: (context) => ReceiptBloc(
              salesRepository: context.read<SalesRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
          BlocProvider<SalesReturnBloc>(
            create: (context) => SalesReturnBloc(
              salesRepository: context.read<SalesRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
          BlocProvider<CustomerLedgerBloc>(
            create: (context) => CustomerLedgerBloc(
              salesRepository: context.read<SalesRepository>(),
              apiClient: sl<ZohoApiClient>(),
            ),
          ),
          BlocProvider<LicenseCubit>(
            create: (context) => LicenseCubit(
              licenseService: sl<LicenseService>(),
              localStorageService: sl<LocalStorageService>(),
              deviceInfoService: sl<DeviceInfoService>(),
            ),
          ),
          BlocProvider<ServerConfigCubit>(
            create: (context) =>
                ServerConfigCubit(apiClient: sl<ZohoApiClient>()),
          ),
          BlocProvider<VoucherPdfBloc>(
            create: (context) => VoucherPdfBloc(
              pdfService: sl<VoucherPdfService>(),
              dbService: sl<HiveDatabaseService>(),
            ),
          ),
        ],
        child: BlocBuilder<ThemeCubit, AppThemeMode>(
          builder: (context, appThemeMode) {
            return MaterialApp(
              title: context.read<OrganizationCubit>().companyName,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: appThemeMode == AppThemeMode.glass
                  ? AppTheme.glassmorphismTheme
                  : AppTheme.darkTheme,
              themeMode: appThemeMode == AppThemeMode.light
                  ? ThemeMode.light
                  : ThemeMode.dark,
              builder: (context, child) => AnimatedGlowBackground(
                themeMode: appThemeMode,
                child: child ?? const SizedBox.shrink(),
              ),
              home: const SessionGateway(),
            );
          },
        ),
      ),
    );
  }
}

/// A stateful gateway that decides which initial page the user should see.
///
/// Gates the application based on:
/// - **Authentication State**: If unauthenticated or loading, routes to [LoginPage] or a loading spinner.
/// - **Core Master Data Status**: If authenticated but has no core masters in the local cache, redirects to [MastersSyncPage].
/// - **Route Selection**: If the user hasn't selected an active sales route, forces redirect to [RouteSelectionPage].
/// - **Dashboard**: When auth, masters, and active route are fully verified, drops into the [DashboardPage].
class SessionGateway extends StatelessWidget {
  const SessionGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        if (authState is Authenticated) {
          return LicenseGate(
            user: authState.user,
            child: BlocBuilder<RouteBloc, RouteState>(
              builder: (context, routeState) {
                if (routeState.isLoading) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  );
                }
                final hasMasters = context
                    .read<SyncRepository>()
                    .hasCoreMasters();
                if (!hasMasters) {
                  return const MastersSyncPage();
                }
                return const DashboardPage();
              },
            ),
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
