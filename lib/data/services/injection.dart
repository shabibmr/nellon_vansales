import 'package:get_it/get_it.dart';
import 'hive_database_service.dart';
import 'firebase_auth_service.dart';
import 'zoho_api_client.dart';
import 'sync_worker.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/sync_repository.dart';
import '../../domain/repositories/sales_repository.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/sync_repository_impl.dart';
import '../repositories/sales_repository_impl.dart';

final GetIt sl = GetIt.instance;

Future<void> setupDependencyInjection() async {
  // 1. Hive Database Service (Requires async init)
  final hiveService = HiveDatabaseService();
  await hiveService.init();
  sl.registerSingleton<HiveDatabaseService>(hiveService);

  // 2. Firebase Authentication Service
  sl.registerLazySingleton<FirebaseAuthService>(() => FirebaseAuthService());

  // 3. Zoho REST API Client
  sl.registerLazySingleton<ZohoApiClient>(() => ZohoApiClient(dbService: sl<HiveDatabaseService>()));

  // 4. Offline Sync Worker
  sl.registerLazySingleton<SyncWorker>(() => SyncWorker(
        dbService: sl<HiveDatabaseService>(),
        apiClient: sl<ZohoApiClient>(),
      ));

  // 5. Repository Implementations
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(authService: sl()));
  sl.registerLazySingleton<SyncRepository>(() => SyncRepositoryImpl(syncWorker: sl(), dbService: sl()));
  sl.registerLazySingleton<SalesRepository>(() => SalesRepositoryImpl(dbService: sl()));
}
