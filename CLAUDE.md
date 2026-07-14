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

`lib/data/services/injection.dart` wires everything using GetIt (`sl`). Registration order matters (Hive must init before anything reads it):
1. `HiveDatabaseService` (async `init()` — opens Hive boxes; the only eager singleton)
2. `FirebaseAuthService`
3. `ZohoApiClient` (depends on `HiveDatabaseService`)
4. `SyncWorker` (depends on Hive + API client)
5. Repository implementations (`AuthRepository`, `SyncRepository`, `SalesRepository`, `SalespersonRepository`)
6. Licensing/device services (`LocalStorageService`, `DeviceInfoService`, `LicenseService`)
7. `VoucherPdfService` (also registered as `VoucherPdfRepository`; a stale-temp-file cleanup runs on boot)

Use `sl<T>()` to resolve anywhere; `setupDependencyInjection()` is called once in `main.dart`.

### Local Storage (Hive)

`HiveDatabaseService` manages three Hive boxes:
- `master_data_box` — customers, items, routes, and session keys (`active_route_id`, `assigned_warehouse_id`)
- `sync_queue_box` — offline transaction queue (`SyncQueueItem` records)
- `local_history_box` — completed local transaction history

Data models in `data/models/` handle JSON serialization for Hive. Domain models in `domain/models/` are clean Dart classes. Conversion is via `fromDomain()` / `fromJson()` on data models.

### Zoho Books Sync

`ZohoApiClient` talks to Zoho Books v3 REST API with OAuth 2.0 (access token auto-refresh via Dio interceptor). Credentials (`_clientId`, `_clientSecret`, `_refreshToken`, `_organizationId`) are set in `zoho_api_client.dart` and can be **overridden at runtime** via `updateCredentials()`, which `ServerConfigCubit` calls after loading remote server config. `_isMockMode()` falls back to a mock sandbox only if credentials are still `YOUR_...` placeholders.

**Important gotcha — transactions are mostly mocked right now.** Three flags in `zoho_api_client.dart` decide what actually hits Zoho (defaults shown; runtime-overridable via `updateMockFlags()`, driven by `ServerConfigCubit`/`ServerConfig`):
- `_mockTransactions = true` → invoices, receipts, returns, and expenses are simulated against a sandbox and **not** pushed live.
- `_mockSalesOrderTransactions = false` → only **sales orders** push live (still requires real credentials).
- `_mockStockTransfers = true` → stock transfers (Issue-to-Van) are simulated and **not** pushed live.
- Master-data downloads (customers, items, routes, etc.) always run live regardless of these flags.

`SyncWorker` manages the offline queue (`syncPendingItems()`):
- Listens for network connectivity changes and triggers sync automatically
- Processes items in order: **customers must sync before invoices** (relational dependency)
- After a new customer syncs, `_resolveTempCustomerIdsInQueue` patches all pending queue items to replace the temporary offline ID with the permanent Zoho ID
- Failed items stay in queue with `SyncStatus.failed` for retry

### State Management (BLoC)

All 16 BLoCs/Cubits are provided globally at the `MaterialApp` level in `app.dart` (`MultiBlocProvider`):

| BLoC / Cubit | Responsibility |
|--------------|----------------|
| `ThemeCubit` | Light / dark / glassmorphism theme mode |
| `OrganizationCubit` | Holds cached `Organization` (currency symbol, company name) — see Multi-Org Context |
| `AuthBloc` | Firebase auth state; fires `AppStarted` on boot |
| `SyncBloc` | Wraps `SyncWorker` streams into BLoC events; exposes sync status/count |
| `RouteBloc` | Route list + active route selection + customer list/search |
| `SalesInvoiceBloc` | Invoice creation workflow |
| `SalesOrderBloc` | Sales order workflow (created + fetched from Zoho) |
| `ExpenseBloc` | Expense logging |
| `ReceiptBloc` | Receipt/collection vouchers with per-invoice allocation |
| `SalesReturnBloc` | Sales returns (per-invoice) |
| `StockTransferBloc` | Stock transfer (Issue-to-Van) workflow |
| `SalespersonCubit` | Salesperson selection/context |
| `CustomerLedgerBloc` | Customer ledger; reads directly from `ZohoApiClient` |
| `LicenseCubit` | Device license verification/provisioning |
| `ServerConfigCubit` | Loads remote server config; injects Zoho credentials via `updateCredentials()` |
| `VoucherPdfBloc` | Drives PDF preview/print/export for vouchers |

### Navigation Flow

`SessionGateway` in `app.dart` drives navigation through several gates:
1. `AuthLoading` → spinner
2. `Unauthenticated` → `LoginPage`
3. `Authenticated` → wrapped in `LicenseGate` (blocks if license disabled/expired)
4. Inside the gate: if `SyncRepository.hasCoreMasters()` is false → `MastersSyncPage` (must download masters first)
5. No active route selected → `RouteSelectionPage`
6. Fully set up → `DashboardPage`

### Business Transactions

Each transaction type has a sync-queue entry (`SyncQueueItem`) and a `ZohoApiClient` method; `SyncWorker.syncPendingItems()` dispatches by type:
- `customer` → `syncCustomer` (always processed first)
- `invoice` → `syncInvoice` *(mocked — see mock flags above)*
- `sales_order` → `syncSalesOrder` *(pushed live)*
- `receipt` → `syncReceiptVoucher` *(mocked)*
- `return` → `syncSalesReturn` *(mocked)*
- `expense` → `syncExpense` *(mocked)*
- `stock_transfer` → `syncStockTransfer` *(mocked)*

### Licensing

`lib/ui/features/licensing/` gates the app behind a device-based license. `LicenseGate` (mounted for authenticated users) triggers `LicenseCubit.checkLicense()`, which auto-provisions first-time logins via `LicenseService` + `DeviceInfoService` (device identity) and `LocalStorageService` (local persistence). On success, `ServerConfigCubit` propagates remote Zoho server config app-wide.

### Multi-Org Context

`OrganizationCubit` (`lib/ui/core/cubit/organization_cubit.dart`) holds the locally-cached `Organization`. **Read currency symbol / company name / currency code from here — never hardcode them.** The `context.org` extension (`lib/ui/core/extensions/org_context_extension.dart`) is the shortcut; `lib/ui/core/utils/currency.dart` handles formatting.

### Reports, Ledger & Voucher PDF

- **Reports** — `lib/ui/features/reports/`: ~13 report pages (item sales, aging receivables, expense summary, invoice/receipts summary, itemwise/customerwise orders and returns summaries, order status, sales summary by customer/item/value, stock report, transactions summary) unified on one shared scaffold, with CSV/PDF/print export.
- **Ledger** — `lib/ui/features/ledger/`: customer ledger (`CustomerLedgerBloc` reads Zoho directly).
- **Voucher PDF** — `lib/ui/features/voucher_pdf/` + `VoucherPdfService`: per-transaction PDF templates (invoice, receipt, expense, sales return, sales order) with print/export actions.

### Shared UI Layer

A shared-widget layer was extracted to keep feature code thin — **reuse these before writing per-feature variants**:
- `lib/ui/core/widgets/` — e.g. `app_text_field`, `item_search_sheet`, `item_line_editor_dialog`, `line_item_list`, `document_list_card`, `editor_footer`, `dialog_scaffolding`, `status_pill`, `empty_state`, `sync_item_card`, `async_search_widget`, `customer_selector_sheet`, `date_range_filter_card`.
- `lib/ui/core/utils/` — `currency.dart`, `date_picker.dart`, `snackbars.dart`.
