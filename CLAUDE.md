# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app
flutter run

# Run on a specific device
flutter run -d <device-id>

# Build Android APK
flutter build apk

# Static analysis
flutter analyze

# Run unit/widget tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Run integration tests
flutter test integration_test/app_test.dart --driver test_driver/integration_test.dart

# Regenerate Hive type adapters (after modifying Hive model classes)
dart run build_runner build --delete-conflicting-outputs
```

## Architecture

This is a **Flutter van sales management app** (package: `van_sales`) targeting Android, with offline-first data sync to Zoho Books.

### Layer Structure

```
lib/
  domain/          # Pure Dart: models + repository interfaces (no Flutter/platform deps)
  data/            # Implementations: Hive models, repository impls, services
  ui/              # BLoC + Views + Widgets, organized by feature
```

**Clean Architecture rule**: `domain/` knows nothing about `data/` or `ui/`. `data/` implements `domain/` interfaces. `ui/` depends on `domain/` interfaces only.

### Dependency Injection

`lib/data/services/injection.dart` wires everything using GetIt (`sl`). Boot order matters:
1. `HiveDatabaseService` (async init — opens Hive boxes)
2. `FirebaseAuthService`
3. `ZohoApiClient`
4. `SyncWorker`
5. Repository implementations

Use `sl<T>()` to resolve anywhere; `setupDependencyInjection()` is called once in `main.dart`.

### Local Storage (Hive)

`HiveDatabaseService` manages three Hive boxes:
- `master_data_box` — customers, items, routes, and session keys (`active_route_id`, `assigned_warehouse_id`)
- `sync_queue_box` — offline transaction queue (`SyncQueueItem` records)
- `local_history_box` — completed local transaction history

Data models in `data/models/` handle JSON serialization for Hive. Domain models in `domain/models/` are clean Dart classes. Conversion is via `fromDomain()` / `fromJson()` on data models.

### Zoho Books Sync

`ZohoApiClient` talks to Zoho Books v3 REST API with OAuth 2.0 (access token auto-refresh via Dio interceptor). Credentials (`_clientId`, `_clientSecret`, `_organizationId`) are hardcoded placeholders in `zoho_api_client.dart` — replace with real values before production.

`SyncWorker` manages the offline queue:
- Listens for network connectivity changes and triggers sync automatically
- Processes items in order: **customers must sync before invoices** (relational dependency)
- After a new customer syncs, `_resolveTempCustomerIdsInQueue` patches all pending queue items to replace the temporary offline ID with the permanent Zoho ID
- Failed items stay in queue with `SyncStatus.failed` for retry

### State Management (BLoC)

All BLoCs are provided globally at the `MaterialApp` level in `app.dart`:

| BLoC | Responsibility |
|------|---------------|
| `AuthBloc` | Firebase auth state; fires `AppStarted` on boot |
| `SyncBloc` | Wraps `SyncWorker` streams into BLoC events; exposes sync status/count |
| `RouteBloc` | Route list + active route selection + customer list/search |
| `SalesInvoiceBloc` | Invoice creation workflow |
| `ThemeCubit` | Light/dark theme toggle |

### Navigation Flow

`SessionGateway` in `app.dart` drives the three-state navigation:
1. `AuthLoading` → spinner
2. `Unauthenticated` → `LoginPage`
3. `Authenticated` + no active route → `RouteSelectionPage`
4. `Authenticated` + active route set → `DashboardPage`

### Business Transactions

The app handles five transaction types, each with a sync queue entry and a corresponding Zoho API method:
- `invoice` → `syncInvoice`
- `receipt` → `syncReceiptVoucher`
- `return` → `syncSalesReturn`
- `expense` → `syncExpense`
- `customer` → `syncCustomer` (always processed first)
