# Review package Task 3
BASE 5f242e5fac66d3650e0613084efd508f78675664
HEAD fd070bbf162606af84f3aa1cb825bcb8a6a827d8
## Commits
fd070bb Provide PrintSettingsCubit from cached Firestore print config.

## Stat
 lib/app.dart                                       | 10 +++++
 lib/data/services/injection.dart                   |  5 +++
 .../print_settings/cubit/print_settings_cubit.dart | 29 +++++++++++++
 test/print_settings_cubit_test.dart                | 49 ++++++++++++++++++++++
 4 files changed, 93 insertions(+)

## Diff
diff --git a/lib/app.dart b/lib/app.dart
index 8f34079..a60b8f6 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -19,20 +19,21 @@ import 'domain/repositories/customer_repository.dart';
 import 'domain/repositories/session_repository.dart';
 import 'domain/repositories/cash_closing_repository.dart';
 import 'domain/repositories/stock_transfer_repository.dart';
 import 'domain/repositories/expense_repository.dart';
 import 'domain/repositories/receipt_repository.dart';
 import 'domain/repositories/sales_return_repository.dart';
 import 'domain/repositories/invoice_repository.dart';
 import 'domain/repositories/sales_order_repository.dart';
 import 'domain/repositories/item_repository.dart';
 import 'domain/repositories/server_config_repository.dart';
+import 'domain/repositories/print_settings_repository.dart';
 import 'ui/features/auth/bloc/auth_bloc.dart';
 import 'ui/features/sync/bloc/sync_bloc.dart';
 import 'ui/features/route/bloc/route_bloc.dart';
 import 'ui/features/sales_invoice/bloc/sales_invoice_list_bloc.dart';
 import 'ui/features/sales_order/bloc/sales_order_list_bloc.dart';
 import 'ui/features/expenses/bloc/expense_list_bloc.dart';
 import 'ui/features/receipts/bloc/receipt_list_bloc.dart';
 import 'ui/features/sales_return/bloc/sales_return_list_bloc.dart';
 
 import 'ui/features/stock_transfer/bloc/stock_transfer_list_bloc.dart';
@@ -49,20 +50,21 @@ import 'data/services/zoho_api_client.dart';
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
+import 'ui/features/print_settings/cubit/print_settings_cubit.dart';
 import 'ui/features/licensing/views/license_gate.dart';
 import 'domain/repositories/thermal_printer_repository.dart';
 import 'ui/features/thermal_print/cubit/thermal_printer_cubit.dart';
 import 'data/services/app_update_service.dart';
 import 'ui/features/app_update/cubit/app_update_cubit.dart';
 import 'ui/features/app_update/views/app_update_gate.dart';
 import 'ui/features/debug/widgets/debug_console_overlay.dart';
 
 /// The root widget of the Van Sales Pro application.
 ///
@@ -116,20 +118,23 @@ class VanSalesApp extends StatelessWidget {
         ),
         RepositoryProvider<SalesOrderRepository>(
           create: (context) => sl<SalesOrderRepository>(),
         ),
         RepositoryProvider<ItemRepository>(
           create: (context) => sl<ItemRepository>(),
         ),
         RepositoryProvider<ServerConfigRepository>(
           create: (context) => sl<ServerConfigRepository>(),
         ),
+        RepositoryProvider<PrintSettingsRepository>(
+          create: (context) => sl<PrintSettingsRepository>(),
+        ),
         RepositoryProvider<VoucherPdfRepository>(
           create: (context) => sl<VoucherPdfRepository>(),
         ),
         RepositoryProvider<DocumentNumberService>(
           create: (context) => sl<DocumentNumberService>(),
         ),
         RepositoryProvider<SyncWorker>(
           create: (context) => sl<SyncWorker>(),
         ),
       ],
@@ -203,20 +208,25 @@ class VanSalesApp extends StatelessWidget {
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
+          BlocProvider<PrintSettingsCubit>(
+            create: (context) => PrintSettingsCubit(
+              repository: sl<PrintSettingsRepository>(),
+            ),
+          ),
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
diff --git a/lib/data/services/injection.dart b/lib/data/services/injection.dart
index 54aab96..b662986 100644
--- a/lib/data/services/injection.dart
+++ b/lib/data/services/injection.dart
@@ -17,35 +17,37 @@ import '../../domain/repositories/report_repository.dart';
 import '../../domain/repositories/voucher_pdf_repository.dart';
 import '../../domain/repositories/thermal_printer_repository.dart';
 import '../../domain/repositories/stock_transfer_repository.dart';
 import '../../domain/repositories/expense_repository.dart';
 import '../../domain/repositories/receipt_repository.dart';
 import '../../domain/repositories/sales_return_repository.dart';
 import '../../domain/repositories/invoice_repository.dart';
 import '../../domain/repositories/sales_order_repository.dart';
 import '../../domain/repositories/item_repository.dart';
 import '../../domain/repositories/server_config_repository.dart';
+import '../../domain/repositories/print_settings_repository.dart';
 import '../repositories/auth_repository_impl.dart';
 import '../repositories/sync_repository_impl.dart';
 import '../repositories/customer_repository_impl.dart';
 import '../repositories/session_repository_impl.dart';
 import '../repositories/cash_closing_repository_impl.dart';
 import '../repositories/salesperson_repository_impl.dart';
 import '../repositories/report_repository_impl.dart';
 import '../repositories/stock_transfer_repository_impl.dart';
 import '../repositories/expense_repository_impl.dart';
 import '../repositories/receipt_repository_impl.dart';
 import '../repositories/sales_return_repository_impl.dart';
 import '../repositories/invoice_repository_impl.dart';
 import '../repositories/sales_order_repository_impl.dart';
 import '../repositories/item_repository_impl.dart';
 import '../repositories/server_config_repository_impl.dart';
+import '../repositories/print_settings_repository_impl.dart';
 import 'local_storage_service.dart';
 import 'device_info_service.dart';
 import 'license_service.dart';
 import 'app_update_service.dart';
 
 /// Global service locator instance (GetIt sl) for dependency injection throughout the app.
 final GetIt sl = GetIt.instance;
 
 /// Bootstraps and registers all global dependencies and repositories.
 ///
@@ -151,20 +153,23 @@ Future<void> setupDependencyInjection() async {
     ),
   );
   sl.registerLazySingleton<ItemRepository>(
     () => ItemRepositoryImpl(dbService: sl(), apiClient: sl()),
   );
 
   // 6. Licensing, Device & Update Services
   sl.registerLazySingleton<LocalStorageService>(() => LocalStorageService());
   sl.registerLazySingleton<DeviceInfoService>(() => DeviceInfoService());
   sl.registerLazySingleton<LicenseService>(() => LicenseService());
+  sl.registerLazySingleton<PrintSettingsRepository>(
+    () => PrintSettingsRepositoryImpl(localStorage: sl<LocalStorageService>()),
+  );
   sl.registerLazySingleton<ServerConfigRepository>(
     () => ServerConfigRepositoryImpl(
       apiClient: sl<ZohoApiClient>(),
       localStorage: sl<LocalStorageService>(),
       licenseService: sl<LicenseService>(),
     ),
   );
   sl.registerLazySingleton<AppUpdateService>(
     () => AppUpdateService(dbService: sl<HiveDatabaseService>()),
   );
diff --git a/lib/ui/features/print_settings/cubit/print_settings_cubit.dart b/lib/ui/features/print_settings/cubit/print_settings_cubit.dart
new file mode 100644
index 0000000..8c23345
--- /dev/null
+++ b/lib/ui/features/print_settings/cubit/print_settings_cubit.dart
@@ -0,0 +1,29 @@
+import 'package:flutter_bloc/flutter_bloc.dart';
+
+import '../../../../domain/models/print_settings.dart';
+import '../../../../domain/repositories/print_settings_repository.dart';
+
+/// App-wide supervisor phone from cached Firestore `server_config/print`.
+class PrintSettingsCubit extends Cubit<PrintSettings> {
+  PrintSettingsCubit({required PrintSettingsRepository repository})
+      : _repository = repository,
+        super(PrintSettings(supervisorPhone: repository.supervisorPhone)) {
+    hydrateDone = _start();
+  }
+
+  final PrintSettingsRepository _repository;
+  late final Future<void> hydrateDone;
+
+  String get supervisorPhone => state.resolvedPhone;
+
+  Future<void> _start() async {
+    await _repository.hydrate();
+    if (!isClosed) {
+      emit(PrintSettings(supervisorPhone: _repository.supervisorPhone));
+    }
+    await _repository.refresh();
+    if (!isClosed) {
+      emit(PrintSettings(supervisorPhone: _repository.supervisorPhone));
+    }
+  }
+}
diff --git a/test/print_settings_cubit_test.dart b/test/print_settings_cubit_test.dart
new file mode 100644
index 0000000..94fc04e
--- /dev/null
+++ b/test/print_settings_cubit_test.dart
@@ -0,0 +1,49 @@
+import 'package:flutter_test/flutter_test.dart';
+import 'package:van_sales/domain/models/print_settings.dart';
+import 'package:van_sales/domain/repositories/print_settings_repository.dart';
+import 'package:van_sales/ui/features/print_settings/cubit/print_settings_cubit.dart';
+
+class FakePrintSettingsRepository implements PrintSettingsRepository {
+  FakePrintSettingsRepository([
+    this._phone = PrintSettings.fallbackSupervisorPhone,
+  ]);
+
+  String _phone;
+  String hydratePhone = '+971 50 111 1111';
+  String refreshPhone = '+971 50 222 2222';
+
+  @override
+  String get supervisorPhone => _phone;
+
+  @override
+  Future<void> hydrate() async {
+    _phone = hydratePhone;
+  }
+
+  @override
+  Future<PrintSettings> refresh() async {
+    _phone = refreshPhone;
+    return PrintSettings(supervisorPhone: _phone);
+  }
+}
+
+void main() {
+  group('PrintSettingsCubit', () {
+    late FakePrintSettingsRepository repository;
+    late PrintSettingsCubit cubit;
+
+    setUp(() {
+      repository = FakePrintSettingsRepository();
+      cubit = PrintSettingsCubit(repository: repository);
+    });
+
+    tearDown(() => cubit.close());
+
+    test('hydrates from cache then refreshes from Firestore', () async {
+      await cubit.hydrateDone;
+
+      expect(cubit.state.supervisorPhone, repository.refreshPhone);
+      expect(cubit.supervisorPhone, repository.refreshPhone);
+    });
+  });
+}
