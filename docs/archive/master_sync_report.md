# Master Data Sync — Plan & Change Report

Date: 2026-05-24
Scope: Wire Zoho Books master-data pull into the offline-first Hive cache, expose a manual sync UI, and gate post-login navigation on master availability.

## Milestone 1

**Goal:** Sync all master data from Zoho into Hive; keep all transaction posting (customer create, invoice, receipt, sales return, expense) **mocked** end-to-end.

**Status:** Complete.

- Master fetchers (organization, warehouses, payment accounts, taxes, expense accounts, routes, items, customers, open invoices) call the real Zoho endpoints when credentials are present (mock fallback otherwise).
- Transaction POSTs (`/contacts`, `/invoices`, `/customerpayments`, `/creditnotes`, `/expenses`) are forced to mock via the `_mockTransactions = true` flag in `ZohoApiClient`, irrespective of credential mode. They return synthetic `zoho_*_<timestamp>` IDs after a 1s delay so the offline queue, ID resolution, and local history flows can be exercised without touching the live books.
- Flip `_mockTransactions` to `false` (next milestone) once each payload shape is validated against Zoho.

---

## 1. Plan

### 1a. Identify what masters are needed

The five real Zoho Books endpoints we already POST to (`/contacts`, `/invoices`, `/customerpayments`, `/creditnotes`, `/expenses`) all reference IDs that must exist locally for offline transaction entry. From that we derived 9 master types to cache:

| Master           | Why it's needed                                               | Zoho endpoint                                   |
| ---------------- | ------------------------------------------------------------- | ----------------------------------------------- |
| Organization     | Currency, fiscal year, time zone for invoice rendering        | `GET /organizations/{org_id}`                   |
| Warehouses       | Resolve `assigned_warehouse_id` to a stock location           | `GET /settings/warehouses`                      |
| Payment Accounts | `deposit_to` account on receipts (bank / cash ledgers)        | `GET /bankaccounts`                             |
| Taxes            | `tax_id` references on invoice lines                          | `GET /settings/taxes`                           |
| Expense Accounts | `account_id` on expense entries                               | `GET /chartofaccounts?filter_by=AccountType.Expense` |
| Routes           | Van-sales route selection (simulated — no native Zoho entity) | (mock)                                          |
| Items            | Stock + pricing for the assigned warehouse                    | `GET /items?warehouse_id=…`                     |
| Customers        | Contacts on the active route                                  | `GET /contacts?contact_type=customer&cf_route_id=…` |
| Open Invoices    | Outstanding invoices for receipt allocation                   | `GET /invoices?status=unpaid`                   |

### 1b. Layering plan

- **Domain**: pure Dart model for each master.
- **Data**: model with `fromJson` (dual-key for Zoho snake_case + camelCase fallback) / `toJson` / `fromDomain`.
- **HiveDatabaseService**: per-master `get*` / `save*` accessors against `master_data_box` (single object for organization, `List<String>` of JSON for the rest).
- **ZohoApiClient**: per-master fetcher hitting the real endpoint when credentials are present, with a mock fallback so the UI still works in dev.
- **SyncWorker**: a `MasterType` enum + a single `syncMaster(MasterType)` dispatcher; `refreshMasterData()` iterates the enum.
- **SyncRepository**: expose `syncMaster`, `refreshMasterData`, and a synchronous `hasCoreMasters()` boolean (true once Routes and Items are cached).

### 1c. UX plan

- **Do not auto-pull masters** on login or route selection.
- A dedicated **Masters Sync page** with one button per master + a "Sync All" button.
- **SessionGateway** routes the user to the Masters Sync page after login if `hasCoreMasters()` is false. Once core masters are present, normal flow resumes (Route Selection → Dashboard).

---

## 2. Changes Made

### 2.1 New domain models (`lib/domain/models/`)
- `warehouse.dart` — `Warehouse(id, name, address, isPrimary)`
- `payment_account.dart` — `PaymentAccount(id, name, accountType, currencyCode, paymentMode)`
- `tax.dart` — `Tax(id, name, percentage, type, isDefault)`
- `expense_account.dart` — `ExpenseAccount(id, name, accountCode, category)`
- `organization.dart` — `Organization(id, name, currencyCode, currencySymbol, fiscalYearStartMonth, timeZone)`
- `open_invoice.dart` — `OpenInvoice(invoiceId, invoiceNumber, customerId, date, dueDate, total, balance, status)`

### 2.2 New data models (`lib/data/models/`)
Matching `*_model.dart` files for each of the above, with dual-key `fromJson`, `toJson`, and `fromDomain` factories. `open_invoice_model.dart` includes a `parseDate` helper for Zoho date strings.

### 2.3 `lib/data/services/hive_database_service.dart`
- Imported the 6 new domain + data models.
- Added accessor pairs against `master_data_box`:
  - `getWarehouses` / `saveWarehouses`
  - `getPaymentAccounts` / `savePaymentAccounts`
  - `getTaxes` / `saveTaxes`
  - `getExpenseAccounts` / `saveExpenseAccounts`
  - `getOrganization` / `saveOrganization` (single object)
  - `getOpenInvoices({String? customerId})` / `saveOpenInvoices` — supports filtering by customer

### 2.4 `lib/data/services/zoho_api_client.dart`
- `fetchCustomers(routeId)` — now calls real `GET /contacts` with `cf_route_id` filter when credentials are configured; mock fallback otherwise.
- `fetchItems(warehouseId)` — now calls real `GET /items?warehouse_id=…`; mock fallback.
- Added 6 new fetchers (each with real endpoint + mock fallback):
  - `fetchWarehouses` → `/settings/warehouses`
  - `fetchPaymentAccounts` → `/bankaccounts`
  - `fetchTaxes` → `/settings/taxes`
  - `fetchExpenseAccounts` → `/chartofaccounts?filter_by=AccountType.Expense`
  - `fetchOrganization` → `/organizations/{org_id}` (returns `Map?`)
  - `fetchOpenInvoices` → `/invoices?status=unpaid`

### 2.5 `lib/data/services/sync_worker.dart`
- Added top-level `MasterType` enum (9 values) + `MasterTypeLabel` extension.
- Added `syncMaster(MasterType type)` — single dispatcher: fetches, persists, emits status, rethrows on failure.
- Refactored `refreshMasterData()` to iterate `MasterType.values`, skipping `customers` when no active route is selected.
- **Removed** the `refreshMasterData()` tail call from `syncPendingItems()` (no implicit master pull after queue drain).

### 2.6 `lib/domain/repositories/sync_repository.dart` & `lib/data/repositories/sync_repository_impl.dart`
- Added `Future<void> syncMaster(MasterType type)`.
- Added `bool hasCoreMasters()` — true when `getRoutes().isNotEmpty && getItems().isNotEmpty`.

### 2.7 `lib/ui/features/route/bloc/route_bloc.dart`
- Removed the `_syncRepository.refreshMasterData()` call from `_onSelectActiveRoute` (no auto-pull on route selection).
- Removed the `SyncRepository` constructor dependency and its import.

### 2.8 `lib/app.dart`
- Updated `RouteBloc` provider — no longer passes `syncRepository`.
- Imported the new `MastersSyncPage`.
- `SessionGateway` flow when `Authenticated`:
  1. If `RouteState.isLoading` → spinner
  2. Else if `!hasCoreMasters()` → `MastersSyncPage`
  3. Else if no active route → `RouteSelectionPage`
  4. Else → `DashboardPage`

### 2.9 `lib/ui/features/sync/views/masters_sync_page.dart` (new)
- AppBar "Sync Master Data".
- "Sync All Masters" button at top (calls `refreshMasterData`).
- ListView of `MasterType.values`, each row with its own sync button, in-flight spinner, and per-row error message.
- After every sync (single or bulk), dispatches `LoadRoutes` so `SessionGateway` re-evaluates and can advance to the next page once core masters are present.

### 2.10 `integration_test/app_test.dart`
- `FakeSyncRepository` updated to implement the two new methods (`syncMaster` is a no-op; `hasCoreMasters` returns `true`).

---

## 3. What is NOT triggered automatically

- Master sync does **not** fire on login.
- Master sync does **not** fire on route selection.
- Master sync does **not** fire at the end of a queue drain.
- The connectivity-based **queue push** (offline transactions → Zoho) still fires on reconnect — that is the offline-first design and unrelated to masters.

All master refreshes are now explicit: user-driven via `MastersSyncPage` buttons.

---

## 4. Verification

`flutter analyze` — clean (only pre-existing `type_init_formals` info lints and one unused-variable warning in `login_page.dart` that predate this change). No new errors or warnings.
