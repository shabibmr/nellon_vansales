# Convert all setState usage to flutter_bloc (Bloc + Cubit, sized by complexity)

## Context
The app's stated state-management standard is BLoC/Cubit, but a grep for `setState(` turned up 25 files still using classic `StatefulWidget` state — leftover from earlier development or ad-hoc dialogs/widgets added since. The user wants a **complete** conversion: every `setState` call replaced with Cubit/BLoC-driven state, including the ones that are purely cosmetic (per user's explicit choice — no exceptions). Two structural duplications surfaced during the audit will be fixed as part of this pass rather than left for later (per user's choice): duplicated GPS-capture logic, and a local cart in `invoice_flow_sheet.dart` that duplicates the existing `SalesInvoiceBloc`.

`flutter_bloc: ^9.1.1` / `bloc: ^9.2.1` are already the latest major versions (verified via pub.dev) — no package upgrade needed. Relevant modern APIs confirmed available: `BlocSelector`, `context.select()/watch()/read()`, `BlocConsumer`, `RepositoryProvider` `dispose` callback. No `bloc_concurrency`/`hydrated_bloc`/`replay_bloc` are currently installed, and no existing Cubit uses event transformers — the codebase's only debounce precedent is a plain `dart:async Timer` in `async_search_widget.dart`. New async-search work should keep using `Timer`-based debounce inside the Bloc rather than pulling in `bloc_concurrency` for a single use site (see Group J — the race it would guard against is better removed by dropping the artificial delay).

One item from the initial 25-file grep is a false positive: `lib\ui\features\voucher_pdf\bloc\voucher_pdf_bloc.dart` has no `setState(` call — the match was the substring inside `_onResetState(`. It's already a clean `Bloc` and is dropped from scope.

## Scope: 24 real files → 11 new classes (5 Bloc, 6 Cubit) + 1 existing-Bloc reuse

### Group A — Reports (13 files, 1 shared generic Bloc)
Files: all of `lib/ui/features/reports/views/*.dart` (item_sales, aging_receivables, stock_report, order_status, customerwise_returns_summary, itemwise_returns_summary, orders_summary_by_customer, itemwise_orders_summary, sales_summary_by_customer_item, sales_summary_by_customer_value, invoice_receipts_summary, expense_summary, transactions_summary).

All 13 share one skeleton: paint Hive cache → fetch from Zoho → `_isLoading` → optional date range → sort field/direction → aggregate → render via the existing shared `SortableReportScaffold` (`lib/ui/core/widgets/sortable_report_scaffold.dart` — reuse as-is, only the state layer changes).

Build:
- `lib/ui/features/reports/bloc/report_state.dart` — generic `ReportState<T>` (`isLoading`, `rows: List<T>`, `range: DateTimeRange?`, `sortField: Object?`, `sortAscending: bool`, `error: String?`).
- `lib/ui/features/reports/bloc/report_event.dart` — `RefreshReport`, `SetDateRange(DateTimeRange?)`, `SetSort(Object field, {bool? ascending})`.
- `lib/ui/features/reports/bloc/report_bloc.dart` — generic `ReportBloc<T> extends Bloc<ReportEvent, ReportState<T>>` parameterized by injected local-fetch/remote-fetch/mapper functions, with `on<RefreshReport>`/`on<SetDateRange>`/`on<SetSort>` handlers.
- Two thin subclasses for the multi-list fetchers: `transactions_summary_report_page.dart` (4 parallel lists via `Future.wait`) and `aging_receivables_report_page.dart` (open invoices + customer names) — give each a small typed payload record as `T` rather than forcing a single-list shape.
- Each of the 13 pages converts from `StatefulWidget` to `StatelessWidget` (or keeps a thin `StatefulWidget` only if the shared scaffold requires a `TickerProvider`/controllers — check `SortableReportScaffold`'s constructor), wrapped in `BlocProvider(create: (_) => ReportBloc<X>(...))`, reading state via `BlocBuilder`/`context.watch`.
- Per-page aggregation logic (`_buildReport()`'s grouping/fold) stays a pure function taking the bloc's raw rows — do not push aggregation into the bloc, only fetch/loading/filter/sort.

Edge cases confirmed by reading `item_sales_report_page.dart` (representative of all 13):
- **Date filtering is coupled inside `_buildReport()`**, applied *before* aggregation — so the Bloc state must carry `range` + `sortField` + `sortAscending`, and the pure per-page `buildReport(state)` function reads them. The Bloc stores sort/filter *state*; the widget keeps the per-page sort *comparator* (the `switch(_sortField)` block) since it references the page-specific enum.
- **Per-page sort enum**: each page has its own `_SortField` enum and the scaffold is typed `SortableReportScaffold<Row, SortEnum>`. Parameterize the Bloc as `ReportBloc<T>` with `sortField` typed `Object?` (or add a second generic `ReportBloc<T, S>`) — decide at implementation; `Object?` keeps the generic simpler.
- **Cache-then-live seeding** (mechanics #6): seed initial state from `_db.getLocalInvoices()` with `isLoading: true`; `RefreshReport` overwrites with the live `fetchInvoices()` result; on failure keep cached rows and emit an error message surfaced via `BlocListener` → `showErrorSnackBar` (mechanics #1), not a blank screen.
- **Reentrancy guard**: `_fetchFromZoho` currently early-returns if already loading (`if (_isLoading) return`) — the `RefreshReport` handler must replicate this (guard on `state.isLoading`, or a droppable transformer). The scaffold's pull-to-refresh (`onRefresh`) maps to `add(RefreshReport())`.

This eliminates ~13x duplicated boilerplate (~40-60 lines each) in favor of one parameterized bloc.

### Group B — dashboard_page.dart (1 file, 1 new cubit)
- `_currentIndex` (bottom-nav/sidebar tab index) → per user's "convert everything" choice, extract into a tiny `DashboardNavCubit extends Cubit<int>` even though it's ephemeral, for consistency with the rest of the app.
- `_todaySales`/`_todayPayments`/`_todayExpenses`/`_todayReturns`/`_completedDeliveries` → `DailyStatsCubit` (business state, re-queried after every transactional flow: invoice, payment, sales return, cash closing, issue-to-van, stock-unloading). Existing callback call sites (`_launchInvoiceFlow`, `_launchPaymentFlow`, `_launchSalesReturnFlow`, etc.) call `context.read<DailyStatsCubit>().refresh()` instead of `_loadDailyStats()` + `setState`.
- This file already uses `ThemeCubit`, `SyncBloc`, `SalesOrderBloc`, `ExpenseBloc`, `ReceiptBloc`, `StockTransferBloc`, `SalesReturnBloc`, `CustomerLedgerBloc` — follow the exact same `BlocProvider`/`context.read` wiring pattern already present in this file.

### Group C — receipt_payment_dialog.dart (1 file, 1 new Bloc)
- `ReceiptAllocationBloc`: holds `_paymentMode`, `_openInvoices` (fetched, cache-then-live), `_allocations` (FIFO-computed), plus a derived `canSubmit` and a new `submitting`/`submitError` (see below).
- **Events** (full list from the audit):
  - `ReceiptAllocationStarted` — seed cached open invoices (`_db.getOpenInvoices`, sorted date-asc) then trigger live refresh.
  - `OpenInvoicesRefreshRequested` (internal) — `await syncMaster(MasterType.openInvoices)` then re-read Hive; on failure **stay silent and keep cached** (current L65-67 swallows), do not emit an error that wipes invoices.
  - `PaymentAmountChanged(String raw)` — the only trigger that re-runs FIFO. Dispatched from the `_amountController` listener (controller stays widget-local).
  - `PaymentModeChanged(String mode)` — pure field set; does **not** re-run FIFO.
  - `InvoiceAllocationEdited(invoiceId, invoiceNumber, String value)` — per-row manual override; mutates that allocation without re-running FIFO.
  - `ReceiptSubmitted` — build temp `ReceiptVoucher`, `saveLocalReceipt`, `enqueueSyncItem`, fire-and-forget `syncPendingItems`; success/failure emitted for a `BlocListener` (pop + snackbar + `onPaymentLogged`).
- **FIFO source-of-truth ordering (critical):** `_allocations` is the model of record; controller text is a *downstream, focus-aware mirror*. Flow is bidirectional — amount/FIFO → controller text (only when not focused), and manual row edit → allocation event. Reconcile controller `.text` in a `BlocListener` respecting focus (mechanics #3); getting this backwards causes cursor jumps or lost edits.
- **Latent bugs to fix in-flight:** (a) submit has *no in-flight guard* today (`_isFormValid` gates the button but nothing blocks a double-tap) → add a `submitting` state; (b) submit has *no try/catch* → add a failure state so a throw doesn't leave the dialog wedged. (c) Decide ordering: a live invoice refresh landing mid-edit currently clobbers in-progress manual allocations via the FIFO re-run — preserve or guard per product intent.
- `_allocationControllers`/`_allocationFocusNodes` (TextEditingController/FocusNode maps) stay widget-local — Flutter view objects requiring `dispose()`; the bloc emits allocation *values* only. `_isFormValid()` moves into state as `canSubmit`.

### Group D — masters_sync_page.dart (1 file, 1 new Bloc)
- `MastersSyncBloc`: per-`MasterType` sync status (`_inFlight`, `_lastError`, `_syncedTypes`), bulk status/success, and `_consoleLogs` (bounded at 100) move into one bloc. `SyncRepository` becomes a bloc dependency (currently `context.read` at several call sites).
- **Events** (full list from the audit):
  - `MastersSyncStarted` — subscribe to `SyncRepository.syncStatusStream`; cancel in `close()` (the one stream that becomes a bloc concern).
  - `SyncStatusLogReceived(String status)` — stream-driven; append a timestamped line, **emit a new bounded list** (mechanics #2), cap at 100. The auto-scroll is UI-only → `BlocListener` (mechanics #3).
  - `SyncOneRequested(MasterType)` — master card tap; also serves the "Retry" pill. Guard: ignore if already in `_inFlight` or `_bulkInFlight`, enforced against current emitted state (event dedup).
  - `SyncAllRequested` — bulk button; loops `MasterType.values`, emitting progressively (start → per-type success/fail → done, mechanics #5). Guard against `_bulkInFlight`.
  - `ConsoleLogsCleared` — CLEAR tap; emit a *new* empty list, not `.clear()`.
- **Capture `hasCoreMasters()` into state**: today `build()` reads `SyncRepository.hasCoreMasters()` synchronously each rebuild to enable the PROCEED button. Move this into emitted state (recompute after each sync) so the button updates reactively.
- **Fixes a latent bug**: the post-loop status write in `_syncAll` is currently unguarded against dispose (mechanics #4) — the emit-after-close guard resolves it.
- Errors here render **inline** (per-type error subtitle + Retry pill, bulk status banner) → all `BlocBuilder`, no snackbars in this file. Cross-bloc dispatches (`RouteBloc.add(LoadRoutes())` after a sync, `SyncBloc`/`AuthBloc` from other buttons) stay widget-side, fired from a `BlocListener` on a "sync completed" state.
- `_tabController` (needs `SingleTickerProviderStateMixin`) and `_scrollController` stay widget-local — they have no `setState` wrapping them, so nothing to convert there.

### Group E — customer_selector_sheet.dart + create_customer_dialog.dart (2 files, 1 shared new Bloc, dedupe)
- Extract `GpsCaptureBloc` (states: idle/capturing/captured(lat,lng)/error) into `lib/ui/core/bloc/gps_capture_bloc.dart`. The two current implementations share an **identical** capture core (permission via **permission_handler** `Permission.locationWhenInUse`, not geolocator; `Geolocator.isLocationServiceEnabled()`; `Geolocator.getCurrentPosition(desiredAccuracy: high, timeLimit: 12s)`) but **differ in side effects** — so the Bloc must be parameterized:
  - **Selector-sheet mode (persist):** requires a `Customer`; writes `repo.updateCustomerGps`, best-effort immediate `ZohoApiClient.updateCustomerGps` (only for non-`temp_` ids, swallowing Zoho failure), and on remote failure enqueues a `customer_gps_update` `SyncQueueItem` + fire-and-forget `syncPendingItems`. Returns an enriched `Customer` (via `Navigator.pop`).
  - **Create-dialog mode (capture-only):** no repo/Zoho/queue writes; just returns raw lat/lng for the caller to drop into text controllers.
  - Model this as `GpsCaptureRequested({Customer? customer, bool persist})` plus states carrying distinct outcomes: `capturing`, `captured(lat,lng, [enrichedCustomer])`, `permissionDenied`, `serviceDisabled`, `failed(message)`. The persist-mode Zoho failure must **not** surface as a user error (current code swallows it).
- Both call sites provide the same `GpsCaptureBloc` via `BlocProvider`, removing the duplicated implementation. Snackbars + `Navigator.pop` + in-dialog coords text are `BlocListener`/`BlocBuilder` concerns (mechanics #1).
- `create_customer_dialog.dart`'s `_isSaving`/`_submit()` → new `CreateCustomerCubit` (states: initial/saving/success/failure). Flow: read+trim controller values, build `Customer` with `temp_cust_<ts>` id + `activeRouteId` (triple-fallback `RouteBloc.state.activeRouteId ?? salesRepo.activeRouteId ?? 'route_default'` — **inject the active route id**, don't read `context` post-await), `saveCustomers`, build Zoho payload (incl. `cf_latitude`/`cf_longitude` custom fields when present), `enqueueSyncItem`, then via `BlocListener`: `RouteBloc.add(LoadRoutes())`, fire-and-forget `syncPendingItems`, `Navigator.pop(newCustomer)`, snackbar, `onCustomerCreated`. **Fixes a latent bug**: current `_submit()` has no try/catch, so a throw leaves `_isSaving=true` forever — the explicit failure state resolves it. The 8 `TextEditingController`s, `_formKey`, and all field validators stay widget-local; the cubit receives already-validated values.
- `customer_selector_sheet.dart`'s in-memory search filter (`StatefulBuilder` + `filtered`/`searchController`) → wrap in a small generic `ListFilterCubit<T>` (`setQuery(String)`, filters a supplied in-memory list), reused for Groups F/I instead of writing near-identical one-offs.

### Group F — item_search_sheet.dart (1 file, reuse Group E's generic filter cubit)
- `_filtered`/`_query` (client-side filter over `widget.items`) → same `ListFilterCubit<Item>` introduced in Group E, not a new bespoke cubit.

### Group G — item_line_editor_dialog.dart (1 file, 1 new Cubit)
- The 3x `onChanged: (_) => setState(() {})` calls exist only to force `subtotal`/`tax`/`total` to recompute live from `TextEditingController` text. Per user's "convert everything" choice: introduce `LineEditorCubit` holding `quantity`/`rate`/`discount` as typed values (not raw controller text), computing `subtotal`/`tax`/`total` as derived getters on the state, with controllers' `onChanged` calling `cubit.updateQuantity(...)` etc. The final `Navigator.pop(context, (qty, rate, discount))` reads from `cubit.state` instead of controller `.text`.

### Group H — route_page.dart (1 file, 1 new Cubit)
- `_selectedRouteId` (pre-confirm highlighted card) → `RouteSelectionUiCubit extends Cubit<String?>`, separate from the existing `RouteBloc` (which already correctly owns the real list/loading state and the actual `SelectActiveRoute` transition). Keep this cubit local to the page (`BlocProvider` scoped to `RouteSelectionPage`, not global in `app.dart`).

### Group I — invoice_flow_sheet.dart (1 file, reuse existing SalesInvoiceBloc + reuse ListFilterCubit for search)
- **Structural fix (per user's choice)**: remove `_localCart` (Map<Item,int>) entirely and drive the existing `SalesInvoiceBloc` from the first tap. **No new bloc events are required** — the existing contract already covers every operation:
  - ADD / increment → `AddToCart(item, 1)` (already carries quantity and does its own `deductStock` stock guard).
  - decrement → `UpdateCartQuantity(item, currentQty - 1)` (auto-removes the line at `qty <= 0`).
  - explicit remove → `RemoveFromCart(item)`.
  - checkout → `CheckoutRequested(customer, notes)` (no more `ClearCart` + `AddToCart` replay).
- **Bind display to `SalesInvoiceState`**: wrap the sheet in `BlocBuilder<SalesInvoiceBloc, SalesInvoiceState>`. Per-row quantity reads `state.cart[item] ?? 0` (the state already exposes a `cart` getter computed from `editingItems` — a drop-in for `_localCart`). Subtotal/tax/total keep being computed in the widget from `state.cart` (state doesn't expose totals).
- **CRITICAL edge case — global shared cart**: `SalesInvoiceBloc` is a single global instance (`app.dart` `MultiBlocProvider`) and its `editingItems` field is **co-used by `sales_invoice_editor_page.dart` and the order-conversion flow (`StartInvoiceFromOrder`)**. It persists across sheet open/close. The sheet must dispatch **`ClearCart` on open (`initState`)** or it will inherit stale items — or worse, a half-edited invoice from the editor page. This is the single most important requirement of the rerouting and the reason the local cart existed.
- **Stock-guard feedback moves to the bloc**: the widget's local clamp + `showErrorSnackBar('Cannot exceed available van stock')` disappears; the bloc emits `errorMessage` on `InsufficientStockException`. Add a `BlocListener` on `state.errorMessage` to keep the snackbar UX, else a rejected increment silently no-ops.
- `_query`/`_searchController` (filter over `_items`, fetched once via `_db.getItems()` in `initState`) → reuse Group E's `ListFilterCubit<Item>` for the search filter; the one-shot `getItems()` read can seed the filter cubit or stay in `initState`.

### Group J — async_search_widget.dart (1 file, 1 new Bloc)
- `AsyncSearchBloc` (states: idle/loading/results(customers|items)/empty), replacing `_isLoading`/`_customerResults`/`_itemResults`/`_hasSearched`/`_activeSearchType`.
- **Correction — no repository search methods exist**: `SalesRepository` has no `searchCustomers`/`searchItems`. The widget does **in-memory filtering** over `getCustomers()`/`getItems()` (customers match name/company case-insensitively + phone on raw query; items match name/sku). The bloc does the same; inject `SalesRepository`.
- **Events**: `SearchTypeChanged(SearchType)` (segmented toggle — also clears query/results), `SearchQueryChanged(String)` (per keystroke, 400ms debounce), `SearchCleared`.
- **Debounce & the out-of-order race**: today a 400ms `Timer` debounces keystrokes, then an *artificial* `Future.delayed(500ms)` "simulates latency" before filtering — and that in-flight delay is uncancellable, so a stale query (or a mid-flight type toggle) can overwrite results with the wrong list. Since the actual filtering is synchronous in-memory work, the clean fix is to **drop the artificial 500ms delay** and filter synchronously after the 400ms `Timer` debounce inside the handler — the race disappears and no `bloc_concurrency` is needed (matches the codebase's existing `Timer` precedent). Only if the simulated latency must be kept, use a `bloc_concurrency` `restartable()` transformer so a newer query cancels the older. Cancel the `Timer` in `close()`.
- **No error state today** (in-memory filter can't throw); add one only if a throwing source is introduced.

## Bloc vs. Cubit: which gets which

Per user direction, don't default everything to Cubit. Use **Bloc** (explicit events, `on<Event>` handlers) for classes with multiple distinct triggers/complex async orchestration or multi-step state machines — matching how the codebase already uses Bloc for its bigger existing classes (`SalesInvoiceBloc`, `SyncBloc`, `SalesOrderBloc`, `ReceiptBloc`, `StockTransferBloc`, `SalesReturnBloc`). Use **Cubit** (plain methods, no event classes) for small, single-purpose state holders — matching the codebase's existing Cubit usage (`ThemeCubit`, `OrganizationCubit`, `LicenseCubit`, `ServerConfigCubit`).

| # | Name | Type | Why |
|---|---|---|---|
| 1 | `ReportBloc<T>` + `ReportState<T>` | **Bloc** | Multiple distinct triggers (refresh, date-range change, sort change) driving one shared engine reused across 13 pages, with real async fetch orchestration (incl. 2 multi-list variants) — event-based dispatch keeps the 13 call sites declarative (`add(RefreshReport())`, `add(SetDateRange(...))`, `add(SetSort(...))`) rather than exposing raw methods on a shared generic. |
| 2 | `DashboardNavCubit` | **Cubit** | One int, one setter. Trivial. |
| 3 | `DailyStatsCubit` | **Cubit** | Single `refresh()` method re-querying local Hive; no distinct event types. |
| 4 | `ReceiptAllocationBloc` | **Bloc** | Multiple distinct triggers (amount changed, per-invoice override, payment mode changed, invoices loaded) each with different FIFO recomputation logic — a real multi-event state machine, not a single setter. |
| 5 | `MastersSyncBloc` | **Bloc** | Per-`MasterType` sync state machine (idle/syncing/synced/error) plus bulk sync plus a log stream — multiple independent event sources feeding one state, same shape as the existing sibling `SyncBloc` it pairs with in this file. |
| 6 | `GpsCaptureBloc` | **Bloc** | Multi-step async flow with distinct stages (request permission → acquire fix → update local cache → optional live Zoho update → enqueue sync) that can fail or be retried at each stage — warrants explicit events (`CaptureRequested`, `PermissionDenied`, `FixAcquired`, etc.) over ad-hoc methods. Shared between Group E's two call sites. |
| 7 | `CreateCustomerCubit` | **Cubit** | One `submit()` flow with a simple saving/success/failure result; no branching event types beyond the one action. |
| 8 | `ListFilterCubit<T>` | **Cubit** | Pure client-side filter over an in-memory list (`setQuery(String)`). Trivial, reused across Groups E/F/I. |
| 9 | `LineEditorCubit` | **Cubit** | Three simple setters (`updateQuantity`/`updateRate`/`updateDiscount`) with derived totals as getters. |
| 10 | `RouteSelectionUiCubit` | **Cubit** | One nullable string, one setter. |
| 11 | `AsyncSearchBloc` | **Bloc** | Distinct triggers (`SearchTypeChanged`, `SearchQueryChanged`, `SearchCleared`) + debounce timer + loading/results/empty states is a real multi-event flow — same shape as `ReceiptAllocationBloc`/`MastersSyncBloc`, not a single setter. |
| 12 | Group I cart | — | No new class — routed through existing `SalesInvoiceBloc`. |

All new Blocs/Cubits follow existing conventions: registered/provided the same way current feature BLoCs are. These are all page/dialog-scoped (not app-wide), so use local `BlocProvider`s at the point of use — confirm the exact existing local-provider pattern (e.g. how `VoucherPdfBloc` or other dialog-scoped blocs are currently provided) before writing new ones, rather than adding these to `app.dart`'s global `MultiBlocProvider`.

## Migration mechanics & edge cases (cross-cutting — applies to every conversion)

These patterns recur across the files and are the parts a naive "move fields into a Cubit" pass gets wrong. Follow them everywhere:

1. **Side effects go in `BlocListener`, never `BlocBuilder`.** Every `showErrorSnackBar`/`showSuccessSnackBar`, `Navigator.pop`, and external callback (`widget.onPaymentLogged`, `widget.onCustomerCreated`, `widget.onInvoiceSubmitted`) is a side effect. Emit an outcome in state (success/failure + message) and react to it in a `listener`. Pure render (loading spinners, inline error text, result lists, enable/disable) binds via `BlocBuilder`/`context.watch`. This is confirmed needed in all 13 report pages (fetch-failure snackbar), receipt submit, create-customer submit, GPS capture, and the invoice sheet's stock-limit feedback.

2. **Emit fresh collections — in-place mutation breaks Equatable.** Several files mutate a `List`/`Set`/`Map` in place then `setState` (masters `_consoleLogs.add(...)`/`.removeAt(0)`/`.clear()`, receipt `_allocations`, masters `_inFlight`/`_syncedTypes`/`_lastError`). If states use `Equatable` (recommended), emitting the same mutated reference is equal to the previous state and the UI won't rebuild. Always emit a new instance (`[...old, x]`, bounded copy, `Set.of(...)`).

3. **Controllers/focus nodes/tab & scroll controllers stay widget-local.** `TextEditingController`, `FocusNode`, `TabController` (needs the ticker mixin), `ScrollController`, and debounce `Timer`s never live in a Bloc. The Bloc holds *values*; the widget owns the view objects and reconciles them. Critical case: receipt allocation controllers must be reconciled from allocation state via a **focus-aware** `BlocListener` (only overwrite a field's `.text` when it is not focused — matches current L124-131) or the user's cursor jumps / edits are lost.

4. **Replace `if (mounted)` / `if (!mounted) return` with emit-after-close guards.** Every async gap currently guarded by a mounted check maps to a Bloc `isClosed`/`emit.isDone` concern. Note this also *fixes a latent bug*: masters `_syncAll`'s post-loop status write (L145-159) is currently **unguarded** and would throw if it completes after dispose.

5. **Progressive multi-emit within one handler.** Cache-then-live loads (reports, receipt) and the per-`MasterType` sync loop emit several states per logical action (cached → loading → live, or start → success/fail → done per type). Use handlers that call `emit` multiple times (or `emit.forEach` for streams); do not model these as one-shot emits.

6. **Cache-then-live seeding.** Pages that paint a Hive snapshot instantly in `initState` then fetch live (all report pages via `_db.getLocalInvoices()`, receipt via `_db.getOpenInvoices()`) must seed the Bloc's **initial state with the cached rows and `isLoading: true`** — do not emit an empty+loading state first, or the instant-paint UX regresses to a blank spinner. On fetch failure, keep the cached rows (offline-first) rather than blanking.

7. **Inject DI singletons and cross-Bloc inputs; don't read `context` after an await.** Pass `HiveDatabaseService`/`ZohoApiClient`/`SyncWorker`/`SalesRepository` and any needed `RouteBloc` state (e.g. `activeRouteId`) into the Bloc constructor. Cross-Bloc dispatches that currently fire post-await from the widget (`RouteBloc.add(LoadRoutes())` in masters and create-customer) move to the widget's `BlocListener` reacting to a "completed" state.

## Execution order (suggested, not required)
1. Group A (reports) first — biggest boilerplate win, fully independent of other groups, validates the generic-bloc pattern early.
2. Group E + F + I's `ListFilterCubit<T>` — build once, reuse three times.
3. Groups B, C, D, G, H, J — independent, can proceed in any order.
4. Group I's `SalesInvoiceBloc` rerouting — do last since it's the only cross-cutting structural change touching an existing bloc's event flow; test the invoice-creation flow thoroughly afterward.

## Verification
- `flutter analyze` after each group to catch dead `setState`/unused imports.
- `flutter test` (existing suite covers `receipt_bloc_test`, `stock_transfer_bloc_test`, `sync_all_test`, etc. — extend with new tests per new class, at minimum for `ReportBloc<T>`, `ReceiptAllocationBloc` (FIFO math + focus-aware reconciliation contract), and the `SalesInvoiceBloc` cart rerouting since that's a behavior change, not just a refactor). Use `bloc_test` (already implied by the existing `*_bloc_test` files) to assert emitted-state sequences, especially the progressive multi-emit handlers (masters per-type loop, cache-then-live).
- **Regression-focused manual runs** (`flutter run`) targeting the edge cases this audit surfaced, not just happy paths:
  - Reports: instant cached paint before live data arrives; fetch failure keeps data + shows snackbar (kill network); date-range + sort after data loads.
  - Receipt: FIFO recompute while a row is focused (cursor must not jump); double-tap Log Receipt (in-flight guard); submit while offline.
  - Masters: console log streams + caps at 100 and rebuilds (in-place-mutation trap); PROCEED button enables reactively after bulk sync; sync completing after navigating away (emit-after-close).
  - GPS: both modes — capture in create-customer (fills fields only) vs selector-sheet (persists + returns enriched customer); permission-denied and location-services-off paths.
  - Create-customer: submit throws (must not wedge the spinner — the fixed latent bug).
  - **Invoice flow (highest risk)**: open sheet → confirm it starts empty even if the invoice editor / order-conversion left items in the global cart (the `ClearCart`-on-open requirement); increment past van stock shows the error snackbar via the bloc; add/decrement/remove/checkout end-to-end; confirm the editor page and order-conversion still work unaffected.
  - Async search: rapid typing then clearing; toggle customer/item type mid-search (no wrong-list results).
- Grep `setState(` across `lib/` at the end — should return zero real matches (the `voucher_pdf_bloc.dart` `_onResetState` substring match is expected and not a real hit).
