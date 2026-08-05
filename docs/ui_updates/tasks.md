# UI Layer Remediation — Detailed Task List

**Source plan:** [plan.md](./plan.md)  
**Scope:** `lib/ui/` and the minimum domain/data/DI seams required to restore clean architecture  
**Status legend:** `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` cancelled  

Use this as the working backlog. Tasks are ordered by dependency within each phase. Prefer **small PRs** (one epic or a coherent slice per PR).

---

## Conventions for all work

- Prefer constructor DI into blocs/cubits; avoid new `sl<>` in widgets.
- UI must depend on **domain repositories / interfaces**, not `ZohoApiClient` / `HiveDatabaseService` / `SyncWorker` directly (except temporary migration shims).
- Keep existing offline-first behavior and mock flags intact.
- Match current BLoC/Cubit + Equatable style unless a task explicitly migrates state shape.
- Add/adjust unit tests with each logic move; run `flutter test` and `flutter analyze` before merge.
- Do not expand scope into unrelated refactors (no wholesale package-import migration unless on Phase 10 polish).

---

## Phase 0 — Foundation (error mapping + DI ground rules)

> Unblocks later phases. Low risk, high leverage.

### T0.1 — User-facing error mapper
- [x] Add a small pure helper (prefer `lib/domain/utils/` or `lib/ui/core/utils/` if UI-only):
  - e.g. `String userFacingMessage(Object error, {String fallback = 'Something went wrong'})`
  - Strip `Exception: ` prefixes
  - Map known domain exceptions (`InsufficientStockException`, network timeouts, etc.) to fixed copy
  - Never return stack traces
- [x] Unit tests: known exception types, unknown `Exception`, plain `String`, nested messages
- [x] Document: blocs emit only mapped strings; widgets never interpolate `$e`

### T0.2 — Standardize unawaited sync triggers
- [x] Inventory all `triggerSync()` / `syncPendingItems()` call sites under `lib/ui`
- [x] Replace bare fire-and-forget with either:
  - `unawaited(...)` (import `dart:async`) when intentional background sync, **or**
  - `await` inside the bloc when the UI must wait
- [x] Prefer `_syncRepository.triggerSync()` over `sl<SyncWorker>().syncPendingItems()` in all new/edited code
- [x] Files known to touch:  
  `sales_invoice_editor_bloc`, `sales_invoice_list_bloc`, `sales_return_editor_bloc`, `sales_order_editor_bloc`, `receipt_editor_bloc`, `expense_editor_bloc`, `stock_transfer_bloc`, `receipt_allocation_bloc`, `sales_return_dialog_cubit`, `gps_capture_bloc`, `expense_log_dialog`, `cash_closing_dialog`, `create_customer_dialog`

### T0.3 — Composition-root rule (document + enforce in review)
- [x] Add a short note to `Claude.md` (or this folder’s README):  
  **“No `sl<>` inside `build()` or leaf widgets; resolve only in page `open` / `BlocProvider.create` / app `MultiBlocProvider`.”**
- [x] Grep checklist for PR review: `sl<` under `lib/ui` should not increase without justification

### T0.4 — Optional: GetIt test harness note
- [x] Document how existing tests reset/register `sl` (if any) so widget-test work later is not blocked

**Exit criteria:** error helper merged; sync triggers consistent; team rule written.

---

## Phase 1 — Error hygiene pass (Track C, partial)

> Replace raw exceptions in UI-facing paths. Can ship independently.

### T1.1 — Blocs/cubits: replace `e.toString()` emissions
- [x] `lib/ui/features/route/bloc/route_bloc.dart`
- [x] `lib/ui/features/voucher_pdf/bloc/voucher_pdf_bloc.dart`
- [x] `lib/ui/features/thermal_print/cubit/thermal_printer_cubit.dart`
- [x] `lib/ui/features/sync/bloc/masters_sync_bloc.dart` (bulk + per-type status strings)
- [x] `lib/ui/features/licensing/cubit/server_config_cubit.dart` / `license_cubit.dart` (user-facing; log-only `$e` in fail-open warnings OK)
- [x] Remaining editor/list blocs that set `errorMessage: e.toString()` or `'$e'` (hardened 2026-08-05: stock_transfer, invoice editor/list, receipt_allocation, sales_return_dialog, gps_capture, customer_ledger, auth, report_bloc)
- [x] Prefer `on Exception catch (e)` over bare `catch (e)`; do not catch `Error`
- [x] Keep specific `on InsufficientStockException` / `FirebaseAuthException` branches

### T1.2 — Widgets: replace raw snackbar errors
- [x] `lib/ui/core/widgets/sortable_report_scaffold.dart` export failure
- [x] `lib/ui/features/reports/widgets/report_bloc_host.dart`
- [x] `lib/ui/features/dashboard/widgets/expense_log_dialog.dart` camera/gallery catch (uses `userFacingMessage`)
- [x] Any other `showErrorSnackBar(context, '... $e')` under `lib/ui` (`open_ledger_transaction` mapped)

### T1.3 — Silent catches audit
- [x] Review `catch (_) {}` in `auth_bloc` tear-down, receipt editor, daily stats
- [x] Either log via project logger (`dart:developer` / app logger) or emit non-fatal state
- [x] Never leave empty catch without a one-line comment explaining why swallow is safe

### T1.4 — Tests
- [x] Update existing bloc tests that assert on raw exception text
- [x] Add cases for mapped messages

**Exit criteria:** no `$e` / `e.toString()` in user-visible UI strings under `lib/ui` (search must be clean).

---

## Phase 2 — Dashboard dialog architecture (Track B)

> Move side-effects out of widgets. Pattern to copy: `SalesReturnDialogCubit`, `ReceiptAllocationBloc`, `CreateCustomerCubit` (partial).

### T2.1 — Expense log dialog
- [x] Identify all Hive / queue / `SyncWorker` / image handling logic in  
  `lib/ui/features/dashboard/widgets/expense_log_dialog.dart`
- [x] Either extend an existing expense cubit/bloc or add `ExpenseLogCubit` under `dashboard/cubit/`
- [x] Cubit deps via constructor: `SalesRepository` or expense write port + `SyncRepository` (+ image pick result as input, not picker in cubit)
- [x] Widget becomes presentational: form fields, dispatches submit, listens for success/error
- [x] Unit tests for submit success, validation failure, sync trigger
- [x] Remove `sl<HiveDatabaseService>` / `sl<SyncWorker>` from the dialog widget

### T2.2 — Cash closing dialog
- [x] Same treatment for `cash_closing_dialog.dart`
- [x] Extract queue write + sync into a cubit (or domain use-case + thin cubit)
- [x] Widget only collects physical cash count and shows expected totals (stats still passed in or read from `DailyStatsCubit`)
- [x] Unit tests for expected closing math (if not already in domain) and submit path

### T2.3 — Create customer dialog (finish the peel)
- [x] Audit `create_customer_dialog.dart` + `create_customer_cubit.dart`
- [x] Ensure **all** queue/sync/GPS wiring lives in cubit; dialog has no `sl<SyncWorker>` / direct API
- [x] Inject `DocumentNumberService` / numbering if needed via constructor (not `sl` in cubit body)
- [x] Align tests in `test/create_customer_cubit_test.dart`

### T2.4 — Invoice flow sheet DI cleanup
- [x] `invoice_flow_sheet.dart`: stop `sl<HiveDatabaseService>().getItems()` in `build`
- [x] Pass items via constructor, `SalesRepository`, or `context.read` from a parent-provided source
- [x] Inject `DocumentNumberService` into `SalesInvoiceEditorBloc` create callback from page/open site
- [x] Keep multi-UOM resolve through `SalesRepository`; inject repo instead of `sl<SalesRepository>()` inside state methods if possible

### T2.5 — Receipt payment / sales return dialogs (spot check)
- [x] Confirm `receipt_payment_dialog` / `sales_return_dialog` only use `sl` at `BlocProvider.create`
- [x] Move any remaining mid-lifecycle `sl` into constructors
- [x] No behavior change expected

**Exit criteria:** dashboard dialog widgets have zero direct Hive/SyncWorker/Zoho imports; logic covered by cubit tests.

---

## Phase 3 — Reports architecture peel (Track A)

> Highest data-layer leakage. Do **one** report end-to-end, then fan out.

### T3.1 — Domain/data seam for reports
- [x] Define `ReportRepository` (or extend existing sales/sync repos) in `lib/domain/repositories/` with methods needed by reports, e.g.:
  - `fetchInvoices()`, `fetchSalesOrders()`, `fetchReceipts()`, `fetchExpenses()`, `fetchSalesReturns()`, `fetchOpenInvoices()`, `fetchCustomers()`, `fetchItems(locationId)`, `fetchRemoteOrders()`, etc. as required
- [x] Implement in `lib/data/` wrapping `ZohoApiClient` + model mapping (keep JSON parsing out of UI)
- [x] Register in `injection.dart`
- [x] **Do not** put Zoho JSON parsing in `lib/ui`

### T3.2 — Pure aggregators
- [x] For the pilot report (recommend **Item Sales**): extract `_ItemSalesRow` + sort/filter aggregation to a pure function/class under e.g.  
  `lib/ui/features/reports/aggregators/item_sales_aggregator.dart`  
  **or** `lib/domain/reports/` if reuse outside UI is likely
- [x] Unit tests for empty, single, multi-invoice, date filter, sort directions
- [x] Aggregator must not depend on Flutter

### T3.3 — Pilot page: Item Sales Report
- [x] Refactor `item_sales_report_page.dart`:
  - `ReportBloc` `fetchRemote` obtained from repository via composition
  - No `sl<ZohoApiClient>` / `sl<HiveDatabaseService>` in the page file
  - Location/salesperson filtering either in repository method or use-case
- [x] Page only: wire host + map state → `SortableReportScaffold`
- [x] Keep UX identical (instant empty/loading, refresh, date filters, export)

### T3.4 — Roll out remaining report pages (checklist)
For each page: remove `sl` + data imports; use repository; extract aggregator if non-trivial; add/adjust tests.

- [x] `aging_receivables_report_page.dart`
- [x] `customerwise_returns_summary_report_page.dart`
- [x] `expense_summary_report_page.dart`
- [x] `invoice_receipts_summary_report_page.dart`
- [x] `itemwise_orders_summary_report_page.dart`
- [x] `itemwise_returns_summary_report_page.dart`
- [x] `order_status_report_page.dart`
- [x] `orders_summary_by_customer_report_page.dart`
- [x] `sales_summary_by_customer_item_report_page.dart`
- [x] `sales_summary_by_customer_value_report_page.dart`
- [x] `shipment_orders_report_page.dart` (already uses `SalesRepository` partially — finish peel)
- [x] `stock_report_page.dart`
- [x] `transactions_summary_report_page.dart`

### T3.5 — Report performance (optional same PR or follow-up)
- [x] Move aggregation into `ReportBloc` when `rows` / date / sort change (emit derived rows) so `build` does not re-sort large lists every rebuild
- [x] Or memoize with previous-state comparison

### T3.6 — Report error path
- [x] Ensure `report_bloc_host` uses `userFacingMessage`
- [x] Loading/error empty states remain exhaustive

**Exit criteria:** `rg "ZohoApiClient" lib/ui/features/reports` is empty; pilot + all report pages green on tests.

---

## Phase 4 — Broader DI / boundary cleanup

### T4.1 — Customer ledger
- [x] Remove `ZohoApiClient` from `CustomerLedgerBloc`
- [x] Add ledger fetch to `SalesRepository` (or dedicated ledger repository)
- [x] Update bloc constructor + app provider registration
- [x] Update any tests

### T4.2 — Stock transfer views
- [x] Remove field-level `sl<HiveDatabaseService>()` from  
  `issue_to_van_page.dart`, `stock_unloading_page.dart`
- [x] Read needed data via `StockTransferBloc` state or inject repository into page only at open

### T4.3 — Core shared widgets
- [x] `item_search_sheet.dart` — accept `SalesRepository` (or a resolve callback) instead of `sl`
- [x] `customer_selector_sheet.dart` — inject deps at `show` / constructor
- [x] `async_search_widget.dart` — pass repository into `BlocProvider.create` from caller when possible
- [x] Update all call sites

### T4.4 — Voucher PDF actions
- [x] `voucher_pdf_actions_widget.dart` should not construct bloc with internal `sl`
- [x] Parent provides `VoucherPdfBloc` (or factory callback with deps already bound)
- [x] Customer lookup via repository, not raw Hive in widget

### T4.5 — List/editor blocs still using `sl` for document numbers
- [x] Inject `DocumentNumberService` into:
  - `sales_invoice_list_bloc`, `sales_invoice_editor` open path
  - `receipt_allocation_bloc`, `sales_return_dialog_cubit`
  - editor pages that currently `sl` at open — OK if only at open; prefer parameter from parent/DI
- [x] `auth_bloc` seeding: inject `DocumentNumberService` instead of `sl` inside method

### T4.6 — Organization / salesperson / daily stats
- [x] Prefer thin repository or keep Hive only in cubit constructors registered at app root (not in random widgets)
- [x] `dashboard_page` should not call `sl<HiveDatabaseService>().ordersOnlyMode` repeatedly; read from cubit/config state

### T4.7 — Licensing mock switch
- [x] `mock_live_switch_tile.dart`: drive only through `ServerConfigCubit`; remove direct `sl<ZohoApiClient>()` if present
- [x] Confirm release builds gate the tile (settings visibility / kDebugMode / license role)

**Exit criteria:** `sl<>` remains only at composition roots; no data service imports in leaf widgets.

---

## Phase 5 — Maintainability splits (P1)

### T5.1 — Split `dashboard_page.dart` (~1100 LOC)
- [x] Extract: app bar / chrome, tab bodies host, navigation helpers, route-to-feature open methods
- [x] Suggested files under `dashboard/widgets/` or `dashboard/views/`:
  - `dashboard_scaffold.dart` / `dashboard_app_bar.dart`
  - keep tab widgets already extracted
  - `dashboard_navigation.dart` for push helpers
- [x] Preserve behavior and providers
- [x] No new features while splitting

### T5.2 — Split `masters_sync_page.dart` (~930 LOC)
- [x] Extract console log panel, per-master cards, bulk actions, progress header into private widgets/files
- [x] Keep page as orchestration + `BlocConsumer`

### T5.3 — Split `customer_ledger_page.dart` (~850 LOC)
- [x] Extract filter header, customer selector section, ledger table/list, transaction tile
- [x] Keep `open_ledger_transaction` util; ensure mounted checks remain

### T5.4 — Split `item_line_editor_dialog.dart` if still > ~400 after nearby work
- [x] Separate UOM selector, qty field, totals preview into child widgets
- [x] Keep form key / IME behavior intact

### T5.5 — Async state shape (incremental)
- [x] Pick one high-traffic feature (e.g. list blocs or `ReportState`) and either:
  - migrate to sealed `initial/loading/loaded/error`, **or**
  - document invariants + add tests that impossible combos are not emitted
- [x] Do **not** big-bang all states in one PR

### T5.6 — Analyzer tightening
- [x] Update `analysis_options.yaml` with strict language settings + `unawaited_futures`, `prefer_final_locals`
- [x] Run `flutter analyze`; fix or narrowly ignore with comments
- [x] Enable `avoid_catches_without_on_clauses` after Phase 1 if clean enough

**Exit criteria:** largest pages under ~400–500 LOC each; analyzer stricter without blocking main.

---

## Phase 6 — Theme consistency (P2)

### T6.1 — Token audit
- [x] Grep `Colors.` under `lib/ui` excluding `app_theme.dart` and PDF templates
- [x] Replace with `Theme.of(context).colorScheme.*` or `AppTheme.*` tokens
- [x] Priority: masters_sync console, list FAB white, invoice_flow delete red, receipt allocations grey text

### T6.2 — Typography
- [x] Replace raw `TextStyle(fontSize: …)` in non-PDF UI with `textTheme` styles
- [x] Skip `voucher_pdf/templates/*`

### T6.3 — MediaQuery specificity
- [x] Replace remaining `MediaQuery.of(context)` with `sizeOf` / `viewInsetsOf` / `paddingOf`  
  (`item_line_editor_dialog`, `issue_to_van_page`)

**Exit criteria:** material UI uses theme/tokens; PDF exempt.

---

## Phase 7 — Accessibility (Track D, partial)

### T7.1 — Semantics on primary dashboard actions
- [x] Wrap or label: FAB/actions, van action tiles, theme toggle, sync affordance, tab bar destinations
- [x] Use `Semantics(button: true, label: '...')` or `tooltip` + `semanticLabel` on icons

### T7.2 — Forms and destructive actions
- [x] Ensure text fields have labels
- [x] Delete/remove icon buttons get semantic labels (“Remove line item”, etc.)

### T7.3 — Tap target pass
- [x] Audit custom chips/metric cards; enforce min 48×48 where interactive

### T7.4 — Optional widget test
- [x] One semantics smoke test using `find.bySemanticsLabel`

**Exit criteria:** core sales path usable with TalkBack/VoiceOver for primary actions (manual device check).

---

## Phase 8 — Localization spike (Track D, partial)

### T8.1 — Enable Flutter gen-l10n
- [x] `pubspec.yaml`: `generate: true` + flutter_localizations / intl as needed
- [x] Add `l10n.yaml` + `lib/l10n/app_en.arb`
- [x] Wire `MaterialApp` localizationsDelegates + supportedLocales

### T8.2 — Extract pilot strings
- [x] Login page strings
- [x] Dashboard chrome (tab labels, search hint, common snackbars)
- [x] Leave reports/editors for later waves

### T8.3 — Process
- [x] Prefer parameterized ARB messages (no string concat for dynamic parts)
- [x] Document “new UI strings go through ARB” in Claude.md

**Exit criteria:** app builds with l10n; login + dashboard chrome infrastructure live (English only is fine initially).

---

## Phase 9 — Widget tests (P2)

### T9.1 — Test utilities
- [x] Helper to pump app shell with mocked repositories / fake blocs
- [x] Avoid real Hive/Firebase

### T9.2 — Critical paths
- [x] Login page: phone validation UI + OTP field visibility driven by `AuthBloc` states
- [x] One editor: error snackbar on failure; submit disabled while saving
- [x] One report page: loading then empty/data scaffold

### T9.3 — CI
- [x] Ensure `flutter test` includes new files; no flaky `pumpAndSettle` without bounds

**Exit criteria:** ≥3 meaningful widget tests green in CI.

---

## Phase 10 — Polish (P3)

- [x] Dashboard hot paths: add `buildWhen` / `BlocSelector` where nested builders over-rebuild
- [x] List pages: switch large dynamic lists to `ListView.builder` if profiling shows jank
- [x] Optional: migrate UI imports to `package:van_sales/...` (large noisy PR — isolate)
- [x] Optional goldens for `StatusPill`, `VanMetricCard`, `EmptyState`
- [x] Re-run full checklist scorecard; update plan.md scorecard statuses

---

## Suggested PR sequence

| PR | Phases / tasks | Risk | Approx. effort |
|----|----------------|------|----------------|
| **PR1** | T0.1–T0.3, T1.* | Low | S |
| **PR2** | T2.1–T2.3 (dialogs) | Med | M |
| **PR3** | T2.4–T2.5, T4.3 partial | Med | S–M |
| **PR4** | T3.1–T3.3 (report seam + pilot) | Med | M |
| **PR5** | T3.4 roll-out (can split 2–3 PRs) | Med | L |
| **PR6** | T4.1–T4.7 remaining DI | Med | M |
| **PR7** | T5.1–T5.4 file splits | Low | M |
| **PR8** | T5.5–T5.6 analyzer + state | Med | M |
| **PR9** | T6.* theme | Low | S |
| **PR10** | T7.* a11y | Low | S |
| **PR11** | T8.* l10n spike | Med | M |
| **PR12** | T9.* widget tests | Low | S–M |
| **PR13** | T10 polish | Low | S |

---

## Definition of done (whole program)

1. `lib/ui` has **no** imports of `ZohoApiClient` (ledger/reports/stock/dialogs cleaned). — **done for product UI**; remaining: `server_config_cubit` (credential injection seam) only
2. `sl<>` only at composition roots (count documented; leaf widgets clean). — **mostly**: editors/PDF/masters use domain repos; composition-root `sl` at dialog open / app providers OK; org/salesperson cubits still Hive at app root
3. User-visible errors never show raw exception dumps. — **done**
4. Largest pages split; dashboard/masters/ledger maintainable. — **mostly** (masters_sync still large)
5. Analyzer strict flags enabled with clean analyze on main. — **options enabled**
6. Semantics on primary dashboard actions; l10n infrastructure present. — **a11y done** (VanActionTile, sync chip, theme tile, remove line); **l10n skipped by request**
7. Widget tests cover login + one editor + one report path. — **done** (login, report scaffold, semantics smoke + empty/status)
8. All existing unit tests updated and green; offline + mock flags still work. — **targeted suites green**

---

## Tracking

| Phase | Owner | Target | Status |
|-------|-------|--------|--------|
| 0 Foundation | | | `[x]` |
| 1 Error hygiene | | | `[x]` (hardened) |
| 2 Dashboard dialogs | | | `[x]` |
| 3 Reports | | | `[x]` |
| 4 DI cleanup | | | `[x]` (server_config exception documented) |
| 5 Splits + analyzer | | | `[x]` / masters still large |
| 6 Theme | | | `[x]` (as landed) |
| 7 A11y | | | `[x]` |
| 8 l10n | | | `[-]` skipped by request |
| 9 Widget tests | | | `[x]` |
| 10 Polish | | | `[x]` (semantics smoke + test hygiene) |

### Hardening follow-up (2026-08-05)

- [x] `FakeSalesRepository.fetchCustomerLedger` on test fakes
- [x] `CreateCustomerCubit` test injects `SyncRepository`
- [x] Map remaining user-facing `e.toString()` / `$e` via `userFacingMessage`
- [-] Wire l10n delegates + pilot strings (**skipped**)
- [x] Dashboard Semantics + Phase 9 widget tests
- [x] Peel Zoho/Hive from stock transfer, GPS, editors, voucher PDF, daily stats, masters logout gate

---

## Quick command cheatsheet

```bash
# Find remaining architecture leaks
rg "ZohoApiClient|HiveDatabaseService|SyncWorker" lib/ui

# Service locator surface
rg "sl<" lib/ui

# Raw errors in UI
rg "e\\.toString\\(\\)|\\\$e" lib/ui

# Accessibility gap
rg "Semantics\\(|semanticLabel" lib/ui

# Verify
flutter analyze
flutter test
```
