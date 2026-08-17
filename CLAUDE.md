# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app
flutter run

# Run on a specific device
flutter run -d <device-id>

# Build Android APK (all ABIs)
flutter build apk

# Fast release APK for van phones (arm64-v8a only, skips clean/build_runner)
pwsh -File scripts/build_apk_arm64.ps1
pwsh -File scripts/build_apk_arm64.ps1 -SkipPub -ApkName app-nellon-release.apk

# Static analysis
flutter analyze

# Run unit/widget tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Run integration tests
flutter test integration_test/app_test.dart --driver test_driver/integration_test.dart

```

`analysis_options.yaml` excludes `scratch/**` and `test/test_org_sync.dart` from the analyzer — `scratch/` holds ad-hoc, uncompiled debugging scripts and isn't part of the app.

## Architecture

This is a **Flutter van sales management app** (package: `van_sales`) targeting Android, syncing sales transactions to Zoho Books.

### Layer Structure

```
lib/
  domain/          # Pure Dart: models, repository interfaces, domain/utils (no Flutter/platform deps)
  data/            # Implementations: Hive models, repository impls, services
  ui/              # BLoC + Views + Widgets, organized by feature
```

**Clean Architecture rule**: `domain/` knows nothing about `data/` or `ui/`. `data/` implements `domain/` interfaces. `ui/` depends on `domain/` interfaces only.

`domain/utils/` holds pure business-rule helpers reused across repositories and the UI: `money_math.dart` (rounds every money-bearing getter to 2dp to stop float drift from compounding across totals), `stock_rules.dart` (`InsufficientStockException`), `phone_normalizer.dart` (E.164 normalization for comparisons), `amount_in_words.dart` (currency-in-words for vouchers), `voucher_content_fingerprint.dart` (stable per-voucher-type content hashes used for "up to date" refresh messaging — deliberately narrower than full model equality, which is noisy from stock/tax-name/unit-conversion fields rebuilt off Zoho JSON).

### Dependency Injection

`lib/data/services/injection.dart` wires everything using GetIt (`sl`). Registration order matters (Hive must init before anything reads it):
1. `HiveDatabaseService` (async `init()` — opens Hive boxes; the only eager singleton)
2. `FirebaseAuthService`
3. `ZohoApiClient` (depends on `HiveDatabaseService`)
4. `DocumentNumberService` (depends on Hive + API client — offline document numbering, see below)
5. `SyncWorker` (depends on Hive + API client + `DocumentNumberService`)
6. Per-domain repository implementations — one interface/impl pair per transaction/entity type (see Repository Layer below)
7. Licensing/device services (`LocalStorageService`, `DeviceInfoService`, `LicenseService`, `AppUpdateService`)
8. `VoucherPdfService` (also registered as `VoucherPdfRepository`; a stale-temp-file cleanup runs on boot)
9. `ThermalPrinterService` (also registered as `ThermalPrinterRepository`)

Use `sl<T>()` only in `injection.dart` and `app.dart` (composition root). Feature widgets and BLoCs take dependencies from `context.read<T>()` / constructors. `setupDependencyInjection()` is called once in `main.dart`.

Sideload APK updates (Firestore `server_config/app_version` + VPS HTTPS) are documented in `docs/app_update.md`.

### Repository Layer

There is no monolithic "sales repository" — each transaction/entity type has its own domain interface (`lib/domain/repositories/`) and implementation (`lib/data/repositories/`): `AuthRepository`, `SyncRepository`, `CustomerRepository`, `SessionRepository`, `CashClosingRepository`, `SalespersonRepository`, `ReportRepository`, `StockTransferRepository`, `ExpenseRepository`, `ReceiptRepository`, `SalesReturnRepository`, `InvoiceRepository`, `SalesOrderRepository`, `ItemRepository`, plus `VoucherPdfRepository` and `ThermalPrinterRepository`. Each is registered as a `RepositoryProvider` in `app.dart` and injected into its corresponding BLoC via `context.read<T>()`. When adding a new transaction type, follow this per-domain pattern rather than growing an existing repository.

### Local Storage (Hive)

`HiveDatabaseService` manages four Hive boxes:
- `master_data_box` — customers, items, routes, and session keys (`active_route_id`, `assigned_warehouse_id`)
- `sync_queue_box` — offline transaction queue (`SyncQueueItem` records)
- `local_history_box` — completed local transaction history
- `item_uom_box` — multi-UOM (unit of measure) conversion data per item

Data models in `data/models/` handle JSON serialization for Hive. Domain models in `domain/models/` are clean Dart classes. Conversion is via `fromDomain()` / `fromJson()` on data models.

Master/reference data synced from Zoho is enumerated by `MasterType` in `sync_worker.dart` (organization, warehouses, paymentAccounts, taxes, expenseAccounts, routes, items, customers, salespersons). **Transactions are never bulk-synced** this way — they go through the offline queue and, when needed live for UI (e.g. open balances), are fetched directly from Zoho.

### Zoho Books Sync

`ZohoApiClient` talks to Zoho Books v3 REST API with OAuth 2.0 (access token auto-refresh via Dio interceptor). Credentials start empty and are injected by `ServerConfigCubit` from Firestore `server_config/zoho` (`client_id`, `client_secret`, `code` = refresh token, `organization_id`), with a `FlutterSecureStorage` cache on `LocalStorageService` so fail-open / offline boots can still refresh. `updateCredentials()` ignores empty remotes so a blank doc cannot wipe a working cache. Changing the OAuth triple clears the Hive access-token cache.

**Save flow is online-first, not offline-first.** `SyncWorker.submitOrEnqueue(item)` is what repositories call to save a transaction: if the device is offline it queues immediately; if online it calls Zoho directly and only falls back to the queue (tagged `[Retryable]` for transient errors, `[Needs Attention]` otherwise) if that call fails. `SyncWorker.syncPendingItems()` then drains the queue:
- Listens for connectivity changes and triggers sync automatically, plus a 60s periodic timer that retries any transient-failed item whose backoff window has elapsed
- Processes items in order: **customers must sync before invoices** (relational dependency)
- After a new customer syncs, `_resolveTempCustomerIdsInQueue` patches all pending queue items to replace the temporary offline ID with the permanent Zoho ID (same pattern exists for temp invoice/order IDs)
- Failed items stay in queue with `SyncStatus.failed` for retry; `_assertStockOrThrow` validates van stock against the local item cache before an invoice/stock-transfer/SO-conversion is queued or sent

`SyncWorker._dispatchSync` routes each queue item type to its `ZohoApiClient.syncX` call: `customer`, `customer_gps_update`, `customer_contact_update`, `invoice`, `sales_order`, `update_sales_order`, `convert_so` (sales order → invoice conversion), `receipt`, `return`, `expense`, `stock_transfer`.

`fetchRoutes()` stays app-local (no Zoho route entity).

### Offline Document Numbering (B5)

`DocumentNumberService` generates duplicate-proof, per-salesperson document numbers (`<prefix><TAG>-#####`, e.g. `SHB-INV-00001`) for `DocType.invoice`, `.salesOrder`, `.receipt`, `.creditNote`. Counters seed from the *higher* of Zoho's existing numbers and the local queue/history, and are monotonic — a device never regresses below a number it already issued, even offline. Concurrent callers within the isolate are serialized through a chained `_tail` future so a read-increment-write can't race. Customers, expenses, stock transfers, GPS/contact updates, and order updates/conversions don't consume a counter.

### State Management (BLoC)

Two scopes exist — don't confuse them:
- **App-level** (provided globally in `app.dart`'s `MultiBlocProvider`): long-lived state needed across screens — session, sync status, routing, and **list** BLoCs per transaction type.
- **Feature-level** (provided locally where the screen/dialog is built): short-lived editing state — one **editor** BLoC per transaction type (create/edit form), plus assorted page-scoped cubits under each feature's own `bloc`/`cubit` folder (e.g. dashboard's `CashClosingCubit`, `CreateCustomerCubit`, `ExpenseLogCubit`).

App-level providers in `app.dart`:

| BLoC / Cubit | Responsibility |
|--------------|----------------|
| `ThemeCubit` | Light / dark / glassmorphism theme mode |
| `OrganizationCubit` | Holds cached `Organization` (currency symbol, company name) — see Multi-Org Context |
| `SalespersonCubit` | Salesperson selection/context |
| `AuthBloc` | Firebase auth state; fires `AppStarted` on boot |
| `SyncBloc` | Wraps `SyncRepository`/`SyncWorker` streams into BLoC events; exposes sync status/count |
| `RouteBloc` | Route list + active route selection + customer list/search |
| `SalesInvoiceListBloc` | Invoice list (create/edit lives in `SalesInvoiceEditorBloc`, feature-scoped) |
| `SalesOrderListBloc` | Sales order list (`SalesOrderEditorBloc` is feature-scoped) |
| `ExpenseListBloc` | Expense list (`ExpenseEditorBloc` is feature-scoped) |
| `ReceiptListBloc` | Receipt/collection voucher list (`ReceiptEditorBloc` is feature-scoped) |
| `SalesReturnListBloc` | Sales return list (`SalesReturnEditorBloc` is feature-scoped) |
| `StockTransferListBloc` | Issue-to-Van / Stock-Unloading lists (online-first Zoho fetch; editor `StockTransferBloc` is route-scoped) |
| `CustomerLedgerBloc` | Customer ledger; reads directly from `ZohoApiClient` |
| `LicenseCubit` | Device license verification/provisioning |
| `ServerConfigCubit` | Hydrates cached Zoho credentials, then injects Firestore `server_config/zoho` via `updateCredentials()` |
| `ThermalPrinterCubit` | Paired printer + paper size selection |
| `AppUpdateCubit` | Sideload APK updates from Firestore `server_config/app_version` |

`lib/ui/core/bloc/` and `lib/ui/core/cubit/` hold generic, reusable state classes instantiated locally wherever needed (not app-provided): `AsyncSearchBloc`, `GpsCaptureBloc`, `LineEditorCubit`, `ListFilterCubit`.

### Navigation Flow

`AppUpdateGate` wraps `SessionGateway` (`app.dart`) at the `MaterialApp.home` level. `SessionGateway` listens to `AuthBloc`:
1. `AuthInitial` → `AppSplashScreen` ("Verifying session…")
2. Not `Authenticated` → `LoginPage`
3. `Authenticated` → wrapped in `LicenseGate` (blocks if license disabled/expired), which watches `RouteBloc`:
   - `routeState.isLoading` → `AppSplashScreen` ("Loading active route…")
   - Else, if `SyncRepository.hasCoreMasters()` is false → `MastersSyncPage` (must download masters first)
   - Else → `DashboardPage`

### Business Transactions

Each transaction type has a sync-queue entry (`SyncQueueItem`), a `SyncWorker._dispatchSync` case, and a `ZohoApiClient.syncX` method:
- `customer` → `syncCustomer` (always processed first); `customer_gps_update` / `customer_contact_update` patch an existing contact only
- `invoice` → `syncInvoice`
- `sales_order` → `syncSalesOrder`; `update_sales_order` → `updateSalesOrder`; `convert_so` → `convertSalesOrderToInvoice`
- `receipt` → `syncReceiptVoucher`
- `return` → `syncSalesReturn`
- `expense` → `syncExpense`
- `stock_transfer` → `syncStockTransfer`

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
- `lib/ui/core/widgets/` — e.g. `app_text_field`, `item_search_sheet`, `item_line_editor_dialog`, `line_item_list`, `document_list_card`, `editor_footer`, `dialog_scaffolding`, `status_pill`, `empty_state`, `sync_item_card`, `async_search_widget`, `customer_selector_sheet`, `date_range_filter_card`, `sortable_report_scaffold`, `confirm_discard_refresh_dialog`, `voucher_refresh_action`.
- `lib/ui/core/utils/` — `currency.dart`, `date_picker.dart`, `date_filter.dart`, `snackbars.dart`, `error_mapper.dart`, `quantity_format.dart`, `permission_dialogs.dart`.

### Bluetooth ESC/POS Thermal Printing

Target: **Nigachi NC-MTP500 series** (and any ESC/POS Bluetooth Classic printer).

- **Domain:** `ThermalPrinterRepository`, `PairedPrinter`, `ThermalPaperSize` (`inch4` default, `inch2`)
- **Data:** `ThermalPrinterService` + `lib/data/services/esc_pos/` ticket builders (`print_bluetooth_thermal` + `esc_pos_utils_plus`)
- **UI:** `ThermalPrinterCubit` (app-level), **Settings** page (paper size + pair + test print), **Thermal** action on `VoucherPdfActionsWidget`
- Paper size and preferred printer persist in Hive `master_data_box`
- A4 PDF Preview/Print/Share path is unchanged

### Zoho API Reference & Tooling (repo root)

These live outside `lib/` and are dev/reference tooling, not part of the app:
- `zohodocs/` — Zoho Books' own per-endpoint OpenAPI/YAML specs (request/response shapes, required OAuth scopes per operation) — check here before guessing a Books API payload or scope.
- `zoho_endpoints/` — standalone Python scripts (`requests` + `python-dotenv`) that exercise Books/Inventory endpoints directly, loading credentials from the root `.env_zoho` (`ZOHO_CLIENT_ID`/`ZOHO_CLIENT_SECRET`/`ZOHO_REFRESH_TOKEN`/`ZOHO_ORG_ID`; scoped `ZohoBooks.fullaccess.all ZohoInventory.fullaccess.all`) rather than a separate local `.env`.
- `scripts/exchange-zoho-oauth.ps1` — exchanges a Zoho Self Client "Generate Code" grant code for an access + refresh token pair (prompts interactively; grant codes expire in minutes).
- `scratch/` — ad-hoc one-off scripts (excluded from `flutter analyze`); not maintained, safe to ignore unless referenced directly.
