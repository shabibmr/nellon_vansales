import 'dart:async';
import 'package:get_it/get_it.dart';
import 'hive_database_service.dart';
import 'firebase_auth_service.dart';
import 'zoho_api_client.dart';
import 'sync_worker.dart';
import 'voucher_pdf_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/sync_repository.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../domain/repositories/salesperson_repository.dart';
import '../../domain/repositories/voucher_pdf_repository.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/sync_repository_impl.dart';
import '../repositories/sales_repository_impl.dart';
import '../repositories/salesperson_repository_impl.dart';
import 'local_storage_service.dart';
import 'device_info_service.dart';
import 'license_service.dart';

/// Global service locator instance (GetIt sl) for dependency injection throughout the app.
final GetIt sl = GetIt.instance;

/// Bootstraps and registers all global dependencies and repositories.
///
/// Ensures local services (like local Hive databases) are initialized asynchronously
/// before registering other services and repositories.
Future<void> setupDependencyInjection() async {
  // 1. Hive Database Service (Requires async init)
  final hiveService = HiveDatabaseService();
  await hiveService.init();
  sl.registerSingleton<HiveDatabaseService>(hiveService);

  // 2. Firebase Authentication Service
  sl.registerLazySingleton<FirebaseAuthService>(() => FirebaseAuthService());

  // 3. Zoho REST API Client
  sl.registerLazySingleton<ZohoApiClient>(
    () => ZohoApiClient(dbService: sl<HiveDatabaseService>()),
  );

  // 4. Offline Sync Worker
  sl.registerLazySingleton<SyncWorker>(
    () => SyncWorker(
      dbService: sl<HiveDatabaseService>(),
      apiClient: sl<ZohoApiClient>(),
    ),
  );

  // 5. Repository Implementations
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(authService: sl()),
  );
  sl.registerLazySingleton<SyncRepository>(
    () => SyncRepositoryImpl(syncWorker: sl(), dbService: sl()),
  );
  sl.registerLazySingleton<SalesRepository>(
    () => SalesRepositoryImpl(dbService: sl(), apiClient: sl()),
  );
  sl.registerLazySingleton<SalespersonRepository>(
    () => SalespersonRepositoryImpl(dbService: sl(), apiClient: sl()),
  );

  // 6. Licensing & Device Services
  sl.registerLazySingleton<LocalStorageService>(() => LocalStorageService());
  sl.registerLazySingleton<DeviceInfoService>(() => DeviceInfoService());
  sl.registerLazySingleton<LicenseService>(() => LicenseService());

  // 7. PDF Document Generation Service
  final voucherPdfService = VoucherPdfService();
  sl.registerLazySingleton<VoucherPdfService>(() => voucherPdfService);
  sl.registerLazySingleton<VoucherPdfRepository>(() => voucherPdfService);
  // Best-effort cleanup of temp PDFs left behind by a previous session
  // (e.g. app was killed before per-share deletion ran).
  unawaited(voucherPdfService.clearStaleTempFiles());
}
