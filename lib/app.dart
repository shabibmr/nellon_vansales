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
import 'domain/repositories/customer_repository.dart';
import 'domain/repositories/session_repository.dart';
import 'domain/repositories/cash_closing_repository.dart';
import 'domain/repositories/stock_transfer_repository.dart';
import 'domain/repositories/expense_repository.dart';
import 'domain/repositories/receipt_repository.dart';
import 'domain/repositories/sales_return_repository.dart';
import 'domain/repositories/invoice_repository.dart';
import 'domain/repositories/sales_order_repository.dart';
import 'domain/repositories/item_repository.dart';
import 'ui/features/auth/bloc/auth_bloc.dart';
import 'ui/features/sync/bloc/sync_bloc.dart';
import 'ui/features/route/bloc/route_bloc.dart';
import 'ui/features/sales_invoice/bloc/sales_invoice_list_bloc.dart';
import 'ui/features/sales_order/bloc/sales_order_list_bloc.dart';
import 'ui/features/expenses/bloc/expense_list_bloc.dart';
import 'ui/features/receipts/bloc/receipt_list_bloc.dart';
import 'ui/features/sales_return/bloc/sales_return_list_bloc.dart';

import 'ui/features/stock_transfer/bloc/stock_transfer_bloc.dart';
import 'ui/features/ledger/bloc/customer_ledger_bloc.dart';
import 'ui/core/cubit/organization_cubit.dart';
import 'ui/core/cubit/salesperson_cubit.dart';
import 'domain/repositories/salesperson_repository.dart';
import 'domain/repositories/report_repository.dart';
import 'domain/repositories/voucher_pdf_repository.dart';
import 'data/services/document_number_service.dart';
import 'data/services/hive_database_service.dart';
import 'data/services/zoho_api_client.dart';
import 'ui/core/widgets/app_splash_screen.dart';
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
import 'domain/repositories/thermal_printer_repository.dart';
import 'ui/features/thermal_print/cubit/thermal_printer_cubit.dart';
import 'data/services/app_update_service.dart';
import 'ui/features/app_update/cubit/app_update_cubit.dart';
import 'ui/features/app_update/views/app_update_gate.dart';

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
        RepositoryProvider<CustomerRepository>(
          create: (context) => sl<CustomerRepository>(),
        ),
        RepositoryProvider<SessionRepository>(
          create: (context) => sl<SessionRepository>(),
        ),
        RepositoryProvider<CashClosingRepository>(
          create: (context) => sl<CashClosingRepository>(),
        ),
        RepositoryProvider<SalespersonRepository>(
          create: (context) => sl<SalespersonRepository>(),
        ),
        RepositoryProvider<ReportRepository>(
          create: (context) => sl<ReportRepository>(),
        ),
        RepositoryProvider<StockTransferRepository>(
          create: (context) => sl<StockTransferRepository>(),
        ),
        RepositoryProvider<ExpenseRepository>(
          create: (context) => sl<ExpenseRepository>(),
        ),
        RepositoryProvider<ReceiptRepository>(
          create: (context) => sl<ReceiptRepository>(),
        ),
        RepositoryProvider<SalesReturnRepository>(
          create: (context) => sl<SalesReturnRepository>(),
        ),
        RepositoryProvider<InvoiceRepository>(
          create: (context) => sl<InvoiceRepository>(),
        ),
        RepositoryProvider<SalesOrderRepository>(
          create: (context) => sl<SalesOrderRepository>(),
        ),
        RepositoryProvider<ItemRepository>(
          create: (context) => sl<ItemRepository>(),
        ),
        RepositoryProvider<VoucherPdfRepository>(
          create: (context) => sl<VoucherPdfRepository>(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (context) => ThemeCubit()),
          BlocProvider<OrganizationCubit>(
            create: (context) => OrganizationCubit(sl<HiveDatabaseService>()),
          ),
          BlocProvider<SalespersonCubit>(
            create: (context) => SalespersonCubit(sl<HiveDatabaseService>()),
          ),
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepository>(),
              salespersonRepository: context.read<SalespersonRepository>(),
            )..add(AppStarted()),
          ),
          BlocProvider<SyncBloc>(
            create: (context) =>
                SyncBloc(syncRepository: context.read<SyncRepository>())
                  ..add(SyncStarted()),
          ),
          BlocProvider<RouteBloc>(
            create: (context) => RouteBloc(
              sessionRepository: context.read<SessionRepository>(),
              customerRepository: context.read<CustomerRepository>(),
            )..add(LoadRoutes()),
          ),
          BlocProvider<SalesInvoiceListBloc>(
            create: (context) => SalesInvoiceListBloc(
              invoiceRepository: context.read<InvoiceRepository>(),
              salesOrderRepository: context.read<SalesOrderRepository>(),
              syncRepository: context.read<SyncRepository>(),
              documentNumberService: sl<DocumentNumberService>(),
            ),
          ),
          BlocProvider<SalesOrderListBloc>(
            create: (context) => SalesOrderListBloc(
              salesOrderRepository: context.read<SalesOrderRepository>(),
            ),
          ),
          BlocProvider<ExpenseListBloc>(
            create: (context) => ExpenseListBloc(
              expenseRepository: context.read<ExpenseRepository>(),
            ),
          ),
          BlocProvider<ReceiptListBloc>(
            create: (context) => ReceiptListBloc(
              receiptRepository: context.read<ReceiptRepository>(),
            ),
          ),
          BlocProvider<SalesReturnListBloc>(
            create: (context) => SalesReturnListBloc(
              salesReturnRepository: context.read<SalesReturnRepository>(),
            ),
          ),
          BlocProvider<StockTransferBloc>(
            create: (context) => StockTransferBloc(
              stockTransferRepository: context.read<StockTransferRepository>(),
              syncRepository: context.read<SyncRepository>(),
            ),
          ),
          BlocProvider<CustomerLedgerBloc>(
            create: (context) => CustomerLedgerBloc(
              customerRepository: context.read<CustomerRepository>(),
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
            create: (context) => ServerConfigCubit(
              apiClient: sl<ZohoApiClient>(),
              localStorage: sl<LocalStorageService>(),
            ),
          ),
          BlocProvider<ThermalPrinterCubit>(
            create: (context) => ThermalPrinterCubit(
              repository: sl<ThermalPrinterRepository>(),
            ),
          ),
          BlocProvider<AppUpdateCubit>(
            create: (context) => AppUpdateCubit(
              updateService: sl<AppUpdateService>(),
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
              home: const AppUpdateGate(child: SessionGateway()),
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
/// - **Authentication State**: Shows splash screen while verifying session; routes to [LoginPage] when unauthenticated.
/// - **Core Master Data Status**: If authenticated but has no core masters in the local cache, redirects to [MastersSyncPage].
/// - **Route Selection**: If the user hasn't selected an active sales route, forces redirect to [RouteSelectionPage].
/// - **Dashboard**: When auth, masters, and active route are fully verified, drops into the [DashboardPage].
class SessionGateway extends StatelessWidget {
  const SessionGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, authState) {
        // Keep SalespersonCubit in sync after login resolution or logout clear.
        if (authState is Authenticated || authState is Unauthenticated) {
          context.read<SalespersonCubit>().refresh(sl<HiveDatabaseService>());
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          if (authState is Authenticated) {
            return LicenseGate(
              user: authState.user,
              child: BlocBuilder<RouteBloc, RouteState>(
                builder: (context, routeState) {
                  if (routeState.isLoading) {
                    return const AppSplashScreen(
                      statusText: 'Loading active route…',
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
          } else if (authState is AuthInitial) {
            return const AppSplashScreen(
              statusText: 'Verifying session…',
            );
          }
          return const LoginPage();
        },
      ),
    );
  }
}
