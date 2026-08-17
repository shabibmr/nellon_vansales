import 'dart:async';
import 'package:get_it/get_it.dart';
import 'hive_database_service.dart';
import 'firebase_auth_service.dart';
import 'zoho_api_client.dart';
import 'document_number_service.dart';
import 'sync_worker.dart';
import 'voucher_pdf_service.dart';
import 'thermal_printer_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/sync_repository.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../../domain/repositories/cash_closing_repository.dart';
import '../../domain/repositories/salesperson_repository.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/repositories/voucher_pdf_repository.dart';
import '../../domain/repositories/thermal_printer_repository.dart';
import '../../domain/repositories/stock_transfer_repository.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../../domain/repositories/sales_return_repository.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../../domain/repositories/sales_order_repository.dart';
import '../../domain/repositories/item_repository.dart';
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
import 'local_storage_service.dart';
import 'device_info_service.dart';
import 'license_service.dart';
import 'app_update_service.dart';

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

  // 3½. Duplicate-proof offline document numbering (B5)
  sl.registerLazySingleton<DocumentNumberService>(
    () => DocumentNumberService(
      dbService: sl<HiveDatabaseService>(),
      apiClient: sl<ZohoApiClient>(),
    ),
  );

  // 4. Offline Sync Worker
  sl.registerLazySingleton<SyncWorker>(
    () => SyncWorker(
      dbService: sl<HiveDatabaseService>(),
      apiClient: sl<ZohoApiClient>(),
      numberService: sl<DocumentNumberService>(),
    ),
  );

  // 5. Repository Implementations
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(authService: sl()),
  );
  sl.registerLazySingleton<SyncRepository>(
    () => SyncRepositoryImpl(syncWorker: sl(), dbService: sl()),
  );
  sl.registerLazySingleton<CustomerRepository>(
    () => CustomerRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<SessionRepository>(
    () => SessionRepositoryImpl(dbService: sl()),
  );
  sl.registerLazySingleton<CashClosingRepository>(
    () => CashClosingRepositoryImpl(dbService: sl()),
  );
  sl.registerLazySingleton<SalespersonRepository>(
    () => SalespersonRepositoryImpl(dbService: sl(), apiClient: sl()),
  );
  sl.registerLazySingleton<ReportRepository>(
    () => ReportRepositoryImpl(apiClient: sl(), dbService: sl()),
  );
  sl.registerLazySingleton<StockTransferRepository>(
    () => StockTransferRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<ExpenseRepository>(
    () => ExpenseRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<ReceiptRepository>(
    () => ReceiptRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<SalesReturnRepository>(
    () => SalesReturnRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<InvoiceRepository>(
    () => InvoiceRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<SalesOrderRepository>(
    () => SalesOrderRepositoryImpl(
      dbService: sl(),
      apiClient: sl(),
      syncWorker: sl(),
    ),
  );
  sl.registerLazySingleton<ItemRepository>(
    () => ItemRepositoryImpl(dbService: sl(), apiClient: sl()),
  );

  // 6. Licensing, Device & Update Services
  sl.registerLazySingleton<LocalStorageService>(() => LocalStorageService());
  sl.registerLazySingleton<DeviceInfoService>(() => DeviceInfoService());
  sl.registerLazySingleton<LicenseService>(() => LicenseService());
  sl.registerLazySingleton<AppUpdateService>(
    () => AppUpdateService(dbService: sl<HiveDatabaseService>()),
  );

  // 7. PDF Document Generation Service
  final voucherPdfService = VoucherPdfService();
  sl.registerLazySingleton<VoucherPdfService>(() => voucherPdfService);
  sl.registerLazySingleton<VoucherPdfRepository>(() => voucherPdfService);
  // Best-effort cleanup of temp PDFs left behind by a previous session
  // (e.g. app was killed before per-share deletion ran).
  unawaited(voucherPdfService.clearStaleTempFiles());

  // 8. Bluetooth ESC/POS thermal printer (2" / 4" tickets)
  final thermalPrinterService = ThermalPrinterService(
    dbService: sl<HiveDatabaseService>(),
  );
  sl.registerLazySingleton<ThermalPrinterService>(() => thermalPrinterService);
  sl.registerLazySingleton<ThermalPrinterRepository>(
    () => thermalPrinterService,
  );
}
