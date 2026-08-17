# Plan: Log Print Server Config Received by Phone

## 1. Goal
Add clear, diagnostic log prints throughout the app lifecycle so developers can see the exact `server_config/zoho` document and parsed `ServerConfig` received by the phone from Firestore.

## 2. Locations for Server Config Log Prints
1. **[`lib/data/services/license_service.dart`](file:///E:/work/nellon/lib/data/services/license_service.dart)**:
   - In `fetchServerConfig()`: Log when reading starts, log raw Firestore map keys and values (including document existence, `client_id`, `organization_id`, presence of `refresh_token`/`code`, and `client_secret` preview).
   - Log errors immediately with full error traces if Firestore fails or times out.
2. **[`lib/data/repositories/server_config_repository_impl.dart`](file:///E:/work/nellon/lib/data/repositories/server_config_repository_impl.dart)**:
   - In `ensureCredentialsLoaded()`: Log whether local storage already had credentials or remote Firestore was consulted, log parsed `ServerConfig.isValid`, and log when credentials are saved to local secure storage.
3. **[`lib/ui/features/licensing/cubit/server_config_cubit.dart`](file:///E:/work/nellon/lib/ui/features/licensing/cubit/server_config_cubit.dart)**:
   - In `setConfig()` and `_hydrate()`: Log when `ServerConfig` is updated and when credentials are set on `ZohoApiClient`.
4. **[`lib/ui/features/licensing/cubit/license_cubit.dart`](file:///E:/work/nellon/lib/ui/features/licensing/cubit/license_cubit.dart)**:
   - In `checkLicense()` and `registerFirstLogin()`: Log the server config received during licensing gate.

## 3. Implementation Tasks
1. Update `LicenseService.fetchServerConfig` with structured `debugPrint` and `AppLogger.info` output displaying raw map and document status.
2. Update `ServerConfigRepositoryImpl.ensureCredentialsLoaded` to log status and validity.
3. Update `ServerConfigCubit.setConfig` and `_hydrate` to log configuration application.
4. Verify all unit tests pass (`flutter test`).
