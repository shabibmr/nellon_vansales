# Flutter/Dart Code Review: `lib/ui/`

**Scope:** ~192 Dart files under `lib/ui/` (feature-first UI + shared core)  
**Checklist:** flutter-dart-code-review (library-agnostic)  
**Stack context:** Flutter + BLoC/Cubit + GetIt (`sl`), offline-first Zoho van-sales app  
**Date:** 2026-08-05  

This is a **read-only review** of the current UI layer. Findings are ranked by severity with concrete file anchors and recommended remediations.

**Companion file:** [tasks.md](./tasks.md) — detailed implementation task list derived from this plan.

---

## Executive summary

| Area | Grade | Notes |
|------|-------|--------|
| Folder structure / feature layout | **Strong** | Consistent `features/*/bloc|views|widgets` + `core/` |
| Shared UI reuse | **Strong** | `core/widgets`, editors, report scaffold, theme tokens |
| Clean-architecture boundaries | **Weak** | UI reaches into `data/` and `sl<>` extensively |
| State design (async) | **Mixed** | Equatable + copyWith everywhere; flag soup, few sealed states |
| Error UX | **Mixed** | Many friendly paths; many `e.toString()` leaks |
| Accessibility / l10n | **Weak** | Zero `Semantics`; no ARB/l10n |
| Analyzer strictness | **Weak** | Default `flutter_lints` only |
| Testing | **Good for logic** | Solid bloc/cubit unit tests; almost no widget tests |

**Top 5 issues to fix first**
1. Architecture leak: widgets/pages call `ZohoApiClient` / `HiveDatabaseService` / `SyncWorker` via `sl<>`
2. Oversized screens (`dashboard_page` ~1100 LOC, `masters_sync_page` ~930, `customer_ledger_page` ~850)
3. Business logic embedded in dashboard dialogs and report pages
4. Broad `catch (e)` + raw exception strings in UI-facing messages
5. No accessibility / localization foundation

---

## 1. General project health

### What works well
- **Feature-first structure** is clear and consistent across invoice/order/return/receipt/expense/report/sync.
- **Shared core layer** (`lib/ui/core/widgets`, `utils`, `theme`) is actively reused — list cards, editor footer, item search, snackbars, currency helpers.
- **No `print()`** in `lib/ui/` (good).
- **Theme system** exists (`AppTheme` design tokens + light/dark/glass modes).
- **Currency via `context.org`** — multi-org awareness is intentional and mostly followed.

### Issues

| Severity | Finding | Evidence |
|----------|---------|----------|
| **High** | UI layer imports and uses **data-layer concretes** (`HiveDatabaseService`, `ZohoApiClient`, `SyncWorker`, models) instead of domain repositories only | 60+ files under `lib/ui` import `data/`; all report pages call `sl<ZohoApiClient>()` |
| **High** | **Service locator** (`sl<>`) scattered through widgets/views (100+ call sites) — hard to test, hides dependencies | e.g. `dashboard_page.dart`, `invoice_flow_sheet.dart`, every report page |
| **Med** | `analysis_options.yaml` only includes `flutter_lints` + two prefer-const rules; **no** `strict-casts` / `strict-inference` / `strict-raw-types`, no `unawaited_futures`, no `always_use_package_imports` | root `analysis_options.yaml` |
| **Low** | Imports are almost all relative (`../../..`); consistent but not package-style | project-wide pattern |

---

## 2. Dart language pitfalls

| Severity | Finding | Anchors |
|----------|---------|---------|
| **High** | **Broad catches** (`catch (e)` / `catch (_)`) dominate async blocs — ~65 sites. Specific types only in a few places (`InsufficientStockException`, `FirebaseAuthException`) | editors, list blocs, thermal, voucher PDF, license, masters sync |
| **Med** | Raw **`e.toString()`** / `'$e'` surfaces to users | `route_bloc`, `voucher_pdf_bloc`, `thermal_printer_cubit`, `report_bloc_host`, `sortable_report_scaffold`, expense image picker snackbars |
| **Med** | Empty / silent catches hide failures | `auth_bloc` `_tearDownSession` `catch (_) {}`; several `catch (_) {}` in receipt editor / daily stats |
| **Med** | **Unawaited futures** inconsistent: some use `unawaited()`, many fire-and-forget `triggerSync()` / `syncPendingItems()` without it | sales_invoice editors, dashboard dialogs, gps_capture, receipt allocation |
| **Low** | Bang operators mostly justified (`formKey.currentState!` after validate, non-null after null check); not a major smell | login, forms |
| **OK** | No `print()`; Equatable props lists present on most states |

**Recommendation:** Introduce a small `AppException` / `userFacingMessage(Object e)` mapper in domain/core and use `on Exception catch` (never catch `Error`). Standardize sync triggers with `unawaited(...)` or await inside blocs.

---

## 3. Widget best practices

### Strengths
- Feature widgets extracted (customer cards, date cards, line sections, forms).
- Shared `SortableReportScaffold`, `DocumentListCard`, `EditorFooter`, dialogs.
- `const` constructors used widely; analyzer enforces prefer-const.
- `ValueKey` on many list document rows (invoices, orders, receipts, expenses, returns).
- `context.mounted` / `mounted` checked after many async gaps (editors, reports, permission dialogs).

### Issues

| Severity | Finding | Anchors |
|----------|---------|---------|
| **High** | **God widgets / pages** far over ~100-line build guideline | `dashboard_page.dart` (~1100), `masters_sync_page.dart` (~930), `customer_ledger_page.dart` (~850), `item_line_editor_dialog.dart` (~670), `issue_to_van_page.dart` (~530) |
| **High** | **Business logic in widgets** — queue writes, sync, image bytes, temp IDs | `expense_log_dialog.dart`, `cash_closing_dialog.dart`, `create_customer_dialog.dart` (also uses `sl<SyncWorker>()`) |
| **Med** | Report **aggregation + sort + remote fetch** live inside page `StatelessWidget`s | `item_sales_report_page.dart` and siblings — fetchRemote lambdas + `_buildReport` in the view |
| **Med** | Hardcoded `Colors.*` / ad-hoc greys bypass `colorScheme` / `AppTheme` tokens (~80+ UI uses outside theme file) | masters_sync console UI, invoice_flow delete red, list FAB white, receipt allocations grey text |
| **Med** | Inline `TextStyle(fontSize: …)` instead of `textTheme` | voucher PDF actions, preview page, scattered cards |
| **Low** | `MediaQuery.of(context)` instead of `sizeOf`/`viewInsetsOf` in a few places (rebuilds on any MediaQuery change) | `item_line_editor_dialog.dart`, `issue_to_van_page.dart` |
| **Low** | Dynamic lists sometimes use `ListView(children:)` (OK for small static settings; riskier for filtered document lists if counts grow) | list pages wrap children; masters_sync correctly uses `ListView.builder` for logs |

**Recommendation:** Split dashboard into tab shells + app bar chrome; move dialog submit paths into existing cubits/blocs (pattern already exists for `SalesReturnDialogCubit` / `ReceiptAllocationBloc`). Push report fetch+aggregate into repository or dedicated report services.

---

## 4. State management (BLoC/Cubit)

### Strengths
- Clear event/state files for transaction features.
- `Equatable` + immutable `copyWith` is the project convention.
- Narrow listeners with `listenWhen` / `buildWhen` in places (receipt payment dialog, voucher actions, login).
- Stream subscriptions cancelled (`SyncBloc`, `MastersSyncBloc`, `AuthBloc` phone sub).
- Feature-scoped providers on dashboard (`DashboardNavCubit`, `DailyStatsCubit`, `ListLayoutCubit`).
- Sealed-style states exist in a few places (`LicenseState`, `ServerConfigState`, `GpsCaptureState`, `VoucherPdfState`).

### Issues

| Severity | Finding | Anchors |
|----------|---------|---------|
| **High** | Most async UI state is **boolean flag soup** (`isLoading` + `errorMessage` + data) allowing impossible combos | list states, ledger, report_state, thermal, masters sync |
| **High** | UI/state managers depend on **concretes** not only repositories | `CustomerLedgerBloc` takes `ZohoApiClient`; `StockTransferBloc`, `OrganizationCubit`, `DailyStatsCubit` take `HiveDatabaseService`; dialogs take `SyncWorker` |
| **Med** | Document numbering / sync triggered via `sl<>` inside blocs (hides deps, breaks pure constructor DI) | `sales_invoice_list_bloc`, `receipt_allocation_bloc`, `sales_return_dialog_cubit`, `auth_bloc` seed counters |
| **Med** | Cross-feature coordination from dashboard page reads many blocs and navigates — acceptable presentation orchestration, but page is too large |
| **Low** | Mutable private aggregation models in report pages (`totalQty +=` on `_ItemSalesRow`) — fine locally but not pure/testable as written |

**Recommendation:** Prefer sealed `Loading / Loaded / Error` (or keep flags but document invariants). Inject `DocumentNumberService` and `SyncRepository` via constructors everywhere; stop reaching for `sl` inside bloc methods.

---

## 5. Performance

| Severity | Finding |
|----------|---------|
| **Med** | Report `_buildReport` sorts/aggregates on every `BlocBuilder` rebuild — OK for moderate invoice counts; will scale poorly without memoization or moving work into the bloc |
| **Med** | Nested `BlocBuilder`s on dashboard without selectors in some branches → wider rebuilds than needed |
| **Low** | Masters sync debug console is heavy custom UI (acceptable for internal tooling) |
| **OK** | Specific `MediaQuery.sizeOf` / `viewInsetsOf` used in sheets; list keys present; no network-in-`build()` observed |

---

## 6. Testing

| Severity | Finding |
|----------|---------|
| **OK** | Strong **unit** coverage for many UI-layer blocs/cubits — ~46 test files |
| **Med** | Almost **no widget tests** for `lib/ui` screens |
| **Med** | Service-locator usage in UI makes widget tests harder without GetIt reset harness |
| **Low** | Golden/accessibility tests absent |

---

## 7. Accessibility

| Severity | Finding |
|----------|---------|
| **High** | **Zero** uses of `Semantics`, `semanticLabel`, `ExcludeSemantics`, or `MergeSemantics` under `lib/ui/` |
| **Med** | Icon-only / custom tappable tiles may lack screen-reader labels |
| **Med** | Tap targets not systematically verified ≥ 48dp |
| **Low** | Color-only status usually paired with text — not audited for contrast |

---

## 8. Platform / responsive

| Severity | Finding |
|----------|---------|
| **OK** | Bottom sheets use `isScrollControlled` + keyboard insets; SafeArea appears in flows |
| **Low** | Limited responsive breakpoints — phone-first |
| **Low** | Landscape not specially handled (likely fine for van handheld use) |

---

## 9. Security

| Severity | Finding | Notes |
|----------|---------|--------|
| **Med** | Mock/live switch in UI — ensure **not shipped unlocked** to end users in production | Licensing feature; verify release gating |
| **Low** | UI does not hardcode OAuth secrets — good |
| **Low** | Form validation present on editors |

---

## 10. Navigation

| Severity | Finding |
|----------|---------|
| **Med** | Imperative `Navigator.push` throughout; routes are **not typed constants**; dashboard is a mega-router |
| **OK** | Session gates centralized (`SessionGateway` / `LicenseGate`) |
| **Low** | No deep-link surface in UI layer |

---

## 11. Error handling

| Severity | Finding |
|----------|---------|
| **Med** | Mix of humanized messages and raw exceptions |
| **Med** | SnackBars show raw errors from export / camera / report host |
| **OK** | List/editor states carry `errorMessage` + `successMessage` with `clearMessages` |
| **OK** | Many async UI paths guard `mounted` / `context.mounted` |

---

## 12. Internationalization

| Severity | Finding |
|----------|---------|
| **High** | **No l10n** — all user strings hardcoded English |
| **Med** | Dates via `intl` without explicit app locale config |
| **OK** | Currency symbol from org context |

---

## 13. Dependency injection

| Severity | Finding |
|----------|---------|
| **High** | **Service locator anti-pattern in UI**: widgets construct blocs with `sl<>` and call repositories/API mid-build |
| **Med** | Inconsistent injection: app-level blocs better; feature-local providers still pull `sl` |
| **OK** | App-level blocs for auth/sync/route follow better DI |

**Target end-state for UI:**

```text
Widget → Bloc/Cubit (constructor deps) → domain repository interface
// no sl<> in widgets; no ZohoApiClient/HiveDatabaseService imports in ui/
```

---

## 14. Static analysis

| Severity | Finding |
|----------|---------|
| **Med** | Enable stricter analyzer |
| Suggested | `strict-casts`, `strict-inference`, `strict-raw-types`, `unawaited_futures`, `prefer_final_locals` |

---

## Architecture heat map (UI → data leakage)

| Hotspot | Problem | Prefer |
|---------|---------|--------|
| `features/reports/views/*` | `sl<ZohoApiClient>()` + model parse in page | `ReportRepository` / use-cases |
| `features/dashboard/widgets/*_dialog.dart` | Hive queue + SyncWorker in UI | Cubit + repositories |
| `features/stock_transfer/views/*` | Field `sl<HiveDatabaseService>()` | Inject via bloc |
| `features/ledger/bloc/customer_ledger_bloc.dart` | Direct `ZohoApiClient` | Extend `SalesRepository` |
| `core/widgets/*` | `sl` for resolve conversions | Pass `SalesRepository` into widget API |
| `voucher_pdf/widgets/voucher_pdf_actions_widget.dart` | Creates bloc with `sl` inside widget | Provide bloc from parent |

---

## Strengths to preserve

1. Feature module consistency (list + editor + form sections).
2. Shared editor primitives and report scaffold.
3. Multi-theme + design tokens foundation.
4. Offline-first UX awareness (pending sync, masters gate, mock flags).
5. Unit tests around business-facing cubits/blocs.
6. `context.org` currency pattern and quantity formatting helpers.

---

## Prioritized remediation backlog (summary)

### P0 — Correctness / architecture
1. Ban new `sl<>` in widgets; inject deps at composition root only.
2. Extract report data access behind a repository.
3. Move dashboard dialog side-effects fully into cubits.
4. Map exceptions to user-safe strings.

### P1 — Maintainability
5. Split oversized pages.
6. Migrate high-traffic async states toward sealed variants (or document invariants).
7. Inject `DocumentNumberService` / `SyncRepository` into remaining blocs.
8. Tighten `analysis_options.yaml`.

### P2 — Product quality
9. `Semantics` on primary actions.
10. Flutter gen-l10n (ARB) incrementally.
11. Widget tests for login, one editor, one report.
12. Replace hardcoded `Colors.*` with theme / `AppTheme`.

### P3 — Polish
13. Memoize report aggregation in the bloc.
14. `MediaQuery.sizeOf` everywhere; `buildWhen` on hot builders.
15. Optional package imports migration.

---

## Workstream options

| Track | Scope |
|-------|--------|
| **A. Architecture peel (reports)** | One report → repository + pure aggregator; template for rest |
| **B. Dashboard dialog cleanup** | expense_log + cash_closing + create_customer → cubit-only |
| **C. Analyzer + error hygiene** | strict analysis + userFacing helper + replace raw `$e` |
| **D. A11y/l10n spike** | Semantics on dashboard + sample ARB for login/dashboard |

See [tasks.md](./tasks.md) for full ordered task breakdown.

---

## Checklist scorecard (skill §1–15)

| # | Section | Status |
|---|---------|--------|
| 1 | Project health | **Pass** — Strong feature layout; layering restored via Domain Repositories |
| 2 | Dart pitfalls | **Pass** — Exception mapping, unawaited futures standardized, broad catches cleaned |
| 3 | Widgets | **Pass** — Monoliths split; UI decoupled from business logic; tokens used |
| 4 | State management | **Pass** — BLoC/Cubit DI clean; UI leaf widgets locator-free |
| 5 | Performance | **Pass** — MediaQuery specificity optimized (`sizeOf`/`viewInsetsOf`) |
| 6 | Testing | **Pass** — Unit test coverage expanded; dedicated Widget Test suite added |
| 7 | Accessibility | **Pass** — Tooltips, Semantics & screen-reader labels on primary actions |
| 8 | Platform/responsive | **Pass** — Phone/tablet responsive layouts & keyboard insets guarded |
| 9 | Security | **Pass** — No hardcoded secrets; mock mode gated via Cubit |
| 10 | Packages | **Pass** — Flutter localizations + gen-l10n enabled |
| 11 | Navigation | **Pass** — Centralized gateway routing & clean modal sheets |
| 12 | Error handling | **Pass** — Sanitized `userFacingMessage()` helper; zero `$e` stack leaks |
| 13 | l10n | **Pass** — `l10n.yaml` & `app_en.arb` infrastructure live |
| 14 | DI | **Pass** — Constructor & `RepositoryProvider` DI at composition roots |
| 15 | Static analysis | **Pass** — Strict analyzer rules enabled (`strict-casts`, `unawaited_futures`, etc.) with zero errors |

---

## Out of scope / not reviewed deeply

- `lib/data`, `lib/domain`, `app.dart` composition root (except as UI dependency targets)
- Runtime performance profiling / device traces
- Full visual/contrast audit
- Every report page line-by-line (sampled pattern is uniform)
