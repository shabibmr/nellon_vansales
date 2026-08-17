# Flutter / Dart Code Review Report

**Date:** 2026-08-17  
**Project:** `van_sales` (Nellon Van Sales — Flutter Android van-sales POS, Zoho Books)  
**Scope:** Full `lib/` + `test/` + project config, reviewed against the library-agnostic Flutter/Dart checklist (architecture, Dart idioms, widgets, BLoC, performance, testing, a11y, platform, security, packages, navigation, errors, l10n, DI, analysis).  
**Method:** Static review of production source, tests, and config. `flutter analyze` was not re-run as part of this pass.  
**Compared to:** `docs/ENTERPRISE_READINESS.md` (2026-06-13) and `reports/2026-07-06_code_review.md`.

---

## Executive summary

The app is a well-structured, production-piloted Flutter codebase. Clean Architecture is mostly real (domain / data / UI), BLoC is used consistently, transaction types are split into their own repository + list/editor BLoCs, and the last two months of work closed several earlier high-severity gaps: Crashlytics, a sanitizing logger, `print()` removal, an in-app update gate, a large unit-test suite, and `context.mounted` discipline after async gaps.

It is **not yet at the bar the checklist sets for a long-lived field product**. The biggest remaining issues are structural, not cosmetic:

1. **Domain depends on data** — repository interfaces import Hive `SyncQueueItem` and `MasterType`.
2. **No CI and a loose analyzer** — `flutter_lints` only; no `strict-casts` / `strict-inference` / `strict-raw-types`; no `.github` workflow.
3. **l10n is scaffolded and unused** — every user-facing string is still hardcoded English, and `MaterialApp` does not even register the generated delegates.
4. **Security at rest is incomplete** — Zoho access tokens live in unencrypted Hive; boxes have no encryption and no schema version.
5. **God services** — `HiveDatabaseService` (~1,870 lines), `ZohoApiClient` (~1,680), `SyncWorker` (~1,100) concentrate too much responsibility.
6. **Accessibility and i18n are not productized** — three `Semantics` sites, no screen-reader pass on forms, no second locale.

**Verdict:** Fit for a controlled Android van-sales pilot. Not yet checklist-green for enterprise rollout. Prioritize the architecture leak, CI + strict analysis, Hive token encryption, and wiring l10n before growing more features.

---

## Scorecard

| # | Area | Rating | Notes |
|---|------|--------|--------|
| 1 | General project health | **Good** | Layer-first + feature-first UI; unused `hive_generator`; no CI |
| 2 | Dart language pitfalls | **Mixed** | Almost no `print`; widespread `catch (e)` / `catch (_)`; relative imports |
| 3 | Widget best practices | **Mixed** | Shared widget layer is real; large `_build*` methods; hardcoded colors/styles |
| 4 | State management | **Good** | List/editor split; Equatable; leftover boolean-flag states; unused BLoC fields |
| 5 | Performance | **Good** | `ListView.separated` + `ValueKey` on lists; `MediaQuery.sizeOf`; no pagination |
| 6 | Testing | **Good** | 104 test files, 13 widget tests; no `bloc_test`, no goldens, thin integration |
| 7 | Accessibility | **Weak** | Semantics on a few dashboard tiles only |
| 8 | Platform | **Good for Android** | Permissions declared; iOS/web are not first-class |
| 9 | Security | **Mixed** | Secure storage for refresh token; access token in Hive; no pinning |
| 10 | Packages | **Good** | Caret ranges; no overrides; `hive_generator` unused |
| 11 | Navigation | **Mixed** | Imperative `Navigator.push` only; typed widget args; no deep links |
| 12 | Error handling | **Good** | Crashlytics + `error_mapper`; no `ErrorWidget.builder` / `BlocObserver` |
| 13 | Internationalization | **Weak** | ARB exists; UI never uses it |
| 14 | Dependency injection | **Good** | GetIt + `RepositoryProvider`; `sl<>` leaks into UI/BLoCs |
| 15 | Static analysis | **Weak** | Default `flutter_lints`; no strict analyzer; no CI gate |

Ratings: **Strong** / **Good** / **Mixed** / **Weak**.

---

## 1. General project health

### What works

- Folder structure is consistent and documented in `CLAUDE.md`:
  - `lib/domain/` — models, repository interfaces, pure utils
  - `lib/data/` — Hive JSON models, repository impls, services
  - `lib/ui/features/<feature>/{bloc,views,widgets}` plus `lib/ui/core/`
- One repository interface/impl pair per transaction type (invoice, order, receipt, return, expense, stock transfer, …). Adding a type has a clear template.
- Shared UI layer exists and is actually reused (`item_search_sheet`, `item_line_editor_dialog`, `document_list_card`, `sortable_report_scaffold`, `editor_footer`).
- No `print()` in `lib/`. Logging goes through `AppLogger` (`debugPrint` + Crashlytics, with credential redaction).
- `pubspec.yaml` uses caret versions, SDK `^3.12.0`, and does not use `dependency_overrides`.
- Platform code (Bluetooth, GPS, secure storage, sideload updates) is behind services/repositories.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| High | Domain layer imports data types, violating the documented clean-architecture rule | `lib/domain/repositories/sync_repository.dart` imports `data/models/sync_queue_item.dart` and `data/services/sync_worker.dart` (`MasterType`). Same `SyncQueueItem` import in customer/invoice/order/receipt/return/expense/cash-closing repository interfaces. |
| Medium | `hive_generator` + `build_runner` are listed but there are **no** `.g.dart` adapters. Persistence is hand-rolled JSON in untyped `Box`es | `pubspec.yaml` vs `HiveDatabaseService` (`late Box _masterBox`, JSON `fromJson`/`toJson`) |
| Medium | `pubspec.yaml` description is still the Flutter template: `"A new Flutter project."` | `pubspec.yaml:2` |
| Medium | No CI. There is no `.github/` workflow that runs `flutter analyze` or `flutter test` | repo root |
| Low | `scratch/` is analyzer-excluded and gitignored; `test/test_org_sync.dart` is also excluded | `analysis_options.yaml` |

**Recommendation:** Move `SyncQueueItem` and `MasterType` into `domain/`. Drop unused `hive_generator` or actually generate typed adapters. Add a GitHub Actions (or equivalent) job that fails on analyzer issues and test failures.

---

## 2. Dart language pitfalls

### What works

- Production code is null-safe and generally well typed.
- `unawaited(...)` is used on purpose (number-counter seed, stale PDF cleanup, credential persist).
- `AppLogger` sanitizes `client_secret` / `refresh_token` / `access_token` / Bearer headers before they hit console or Crashlytics.
- Dart 3 `switch` is used in places (`AuthBloc._messageForBindFailure`, `error_mapper` Dio types).
- `late` is mostly justified (`TabController`, `TextEditingController` created in `initState`, Hive boxes after `init()`).

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| High | **Broad `catch` is the house style.** Almost every network/storage path is `catch (e)` or `catch (_)` with no `on` clause. That also swallows `Error` (programming bugs). Only one typed catch was found (`on DioException` in `zoho_api_client.dart`). | 65+ `catch (` sites under `lib/`; `zoho_api_client.dart` alone has dozens |
| Medium | Null-assertion (`!`) after implicit checks, instead of promotion / `if-case` | `salesperson_repository_impl.dart` (`primary!.id`), `sales_return_dialog.dart` (`state.selectedItem!`), GPS lat/lng formatters |
| Medium | Relative imports everywhere, including domain → data | Checklist wants `package:van_sales/...`. Mixed: `error_mapper.dart` uses package imports; most of the tree uses `../` |
| Medium | UI/BLoC files reach into `data/services` | `auth_bloc.dart` imports `DocumentNumberService` + `sl`; `invoice_flow_sheet.dart` imports `DocumentNumberService`; `OrganizationCubit` / `SalespersonCubit` take `HiveDatabaseService` |
| Low | Unused constructor fields kept alive with `// ignore: unused_field` | `SalesInvoiceListBloc`, `SalesInvoiceEditorBloc`, `SalesOrderEditorBloc`, `SalesReturnEditorBloc`, `ExpenseEditorBloc`, `ReceiptEditorBloc`, `StockTransferBloc`, `session_repository_impl`, `cash_closing_repository_impl` |
| Low | Public APIs return raw `List` / `Map` from Hive (mutable snapshots) | Repository `getCustomers()` / `getItems()` / list states |

`catch (_)` is acceptable for “Firebase may be missing in tests.” Catching every `Object` around OAuth, sync dispatch, and Hive writes hides bugs and makes retry classification harder.

**Recommendation:** Enable `avoid_catches_without_on_clauses`. Catch `DioException`, `TimeoutException`, `SocketException`, and domain exceptions explicitly; let `Error` propagate to Crashlytics. Delete unused BLoC constructor parameters instead of ignoring them.

---

## 3. Widget best practices

### What works

- Feature screens are split into page + form + footer + list-card widgets.
- `const` constructors and `prefer_const_constructors` / `prefer_const_literals_to_create_immutables` are enabled.
- `ValueKey(doc.id)` is used on invoice / order / receipt / return / expense / stock-transfer cards.
- `GlobalKey<FormState>` is limited to forms (correct). No `UniqueKey()` in `build()`.
- Dark / glass / light themes live in `AppTheme` with named tokens.
- `MediaQuery.sizeOf` / `viewInsetsOf` are used (not the deprecated full `MediaQuery.of` subscribe-everything path).
- `SafeArea` is applied on list, editor, login, license, sync, and report scaffolds.
- `LayoutBuilder` is used on dashboard operations/reports and a few dialogs.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | Several widgets still use private `_build*()` helpers instead of extracted widget classes | `login_page.dart`, `masters_sync_page.dart`, `async_search_widget.dart`, `item_line_editor_dialog.dart` (604 lines), `van_action_tile.dart`, `license_gate.dart` |
| Medium | Large feature widgets hold orchestration that belongs in a BLoC/cubit | `invoice_flow_sheet.dart` (504 lines) resolves UOMs, mutates local `_resolvingItemId`, and talks to three repositories from `State` |
| Medium | Colors and text styles bypass `ColorScheme` / `TextTheme` | Hardcoded `Color(0xFF…)` in `sortable_report_scaffold`, `item_search_sheet`, `sync_item_card`; `Colors.grey` / `Colors.white`; raw `TextStyle(fontSize: …)` on login, expense form, sales-order footer |
| Medium | Design tokens exist (`AppTheme.primaryIndigo`) but many call sites still pass `isDark` and pick colors manually instead of `Theme.of(context)` | Dashboard tiles, sheets, list empty-states |
| Low | `Opacity` used to disable tiles (`van_action_tile.dart`) — cheaper than an animation issue, but the tile is still in the semantics tree with `enabled: false` (good) wrapped in `Opacity` (extra saveLayer) | |

`item_line_editor_dialog.dart` is the right *idea* (one shared editor) but it is past the ~80–100 line `build` guideline and still contains several `_buildQuantityField`-style helpers.

**Recommendation:** Extract `_build*` helpers in the largest files into `StatelessWidget`s. Stop threading `isDark` through the dashboard; read `Theme.of(context).brightness` / `colorScheme`. Route leftover hex colors through `AppTheme` or `ColorScheme` extensions.

---

## 4. State management (BLoC)

The project uses **flutter_bloc 9 + Equatable**. App-level list BLoCs live in `app.dart`; editor BLoCs are created on the editor route/sheet. That split matches the documented convention and is a clear improvement over the July review (which called out mixed list+editor BLoCs).

### What works

- Dependencies are constructor-injected (repositories), not constructed inside BLoCs.
- Auth uses mutually exclusive subclasses (`AuthInitial`, `Authenticated`, `Unauthenticated`, `AuthFailure`, OTP states) — the checklist’s preferred shape.
- Invoice list uses an explicit `SalesInvoiceListStatus { initial, loading, success, failure }` rather than boolean soup.
- Equatable + `copyWith` is consistent.
- `buildWhen` is used on editor pages so the whole scaffold does not rebuild on every keystroke.
- `context.mounted` / `mounted` is checked after almost every `await` that then shows a snackbar or navigates.
- Feature-scoped editor BLoCs are disposed with their `BlocProvider` (invoice flow sheet is a good example).
- `PhoneAuthEvent` is a `sealed class` (Dart 3) — the only sealed type in the app.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | Several list/async states still use `isLoading` + nullable data + nullable error — impossible combinations remain representable | `StockTransferListState`, `ExpenseListState`, `ReceiptListState`, `SalesOrderListState`, `CustomerLedgerState`, `ReportState`, `ThermalPrinterState`, `ReceiptAllocationState` |
| Medium | `StockTransferBloc` (the **editor**) is registered as an **app-level** singleton in `app.dart`, contrary to `CLAUDE.md` (“editor is feature-scoped”) | `app.dart` `BlocProvider<StockTransferBloc>`; leftover unused `_syncRepository` field |
| Medium | Cross-BLoC coordination happens in widgets via `context.read<OtherBloc>()` — acceptable as presentation-layer wiring, but `shipment_orders_report_page.dart` drives both `SalesInvoiceListBloc` and `StockTransferBloc` | Works, but the page is a mediator |
| Medium | UI cubits depend on the Hive concrete class | `OrganizationCubit`, `SalespersonCubit` |
| Medium | `CustomerLedgerBloc` is app-scoped for a screen that is opened occasionally | Lives for the whole session |
| Low | No `BlocSelector` anywhere; rebuild narrowing is only via `buildWhen` on a few editors | |
| Low | `filteredInvoices` / `filteredTransfers` are computed on the state object (fine) but the same date-filter copy is duplicated per list state | `date_filter.dart` helps; a shared list-state mixin would DRY this |

Boolean `isLoading` + `errorMessage` on stock-transfer lists can represent `isLoading && errorMessage != null`. Invoice list already shows the better pattern — migrate the rest to the same status enum (or sealed states).

**Recommendation:** Provide `StockTransferBloc` only on the editor route. Replace remaining `isLoading` flags with the invoice-list status enum. Give `OrganizationCubit` a small domain port instead of `HiveDatabaseService`.

---

## 5. Performance

### What works

- Transaction lists use `ListView.separated` + `itemBuilder` + `ValueKey`.
- Concrete `ListView(children: …)` is used for **empty states** (to keep `RefreshIndicator` happy) and for small static settings/drawer/editor forms — acceptable.
- No `MediaQuery.of(context)` full inherited-widget subscription.
- Dashboard uses `LayoutBuilder` to switch sidebar / drawer / grid.
- Network images are not a product surface (logo is a local asset with `errorBuilder`).
- `unawaited` + generation counters (`_fetchGeneration` on invoice list) prevent stale list completions from clobbering newer fetches.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | No pagination. Masters and transaction lists are loaded fully into memory and filtered in Dart | `ItemRepository.getItems()`, customer search, report aggregators, `HiveDatabaseService` list getters |
| Medium | `HiveDatabaseService` is an in-memory + full-box JSON dump (~1,870 lines). Every get deserializes lists | Will hurt at 1k+ customers/items and long history |
| Low | `Image.asset` does not set `cacheWidth` / `cacheHeight` | `app_logo.dart` — minor on a single logo |
| Low | No `RepaintBoundary` around the sales-trend chart | `sales_trend_chart.dart` |
| Low | `invoice_flow_sheet` calls `getItems()` inside `build()` of the outer `StatelessWidget` | Line 40 — cheap if the list is already in RAM, but it runs on every rebuild of the sheet host |

Web deferred-loading is N/A (Android van phones). Intrinsic-size widgets were not found as a hotspot.

**Recommendation:** Page Zoho list fetches and keep an id-indexed Hive cache (customer cache already exists). Do not add `RepaintBoundary` / image-cache tweaks until a profile says so.

---

## 6. Testing

### What works

- **104** test files under `test/`, including dedicated tests for most list/editor BLoCs, repositories, aggregators, sync ID resolution, payload mapping, and money/stock rules.
- **13** widget tests (`test/widgets/`), including semantics on `VanActionTile`, list pages, login, masters sync, report scaffold, thermal preview.
- Integration-test harness exists (`integration_test/app_test.dart`) with fakes for auth/sync so the login surface can render without disk/network.
- External I/O is stubbed (`test/helpers/sales_repository_enqueue_stubs.dart`) rather than hitting Zoho.
- Enterprise review (June) said “~2 of 10 BLoCs, 5 test files.” That gap is largely closed.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | No `bloc_test` / `mocktail` / `mockito` — tests are hand-rolled | `pubspec.yaml` |
| Medium | No golden tests | — |
| Medium | Integration test is a harness, not a critical-path E2E (invoice → receipt → sync) | `integration_test/app_test.dart` |
| Medium | Tests do not run in CI (there is no CI) | — |
| Low | `test/widget_test.dart` is still a model serialization suite, not a widget test | naming lie |
| Low | One test file per class is mostly true; some files are broad (`sales_repository_enqueue_test.dart`, `sync_all_test.dart`) | |

Coverage was not measured in this review. Business-logic tests look well above a thin smoke suite; UI coverage is still a sample, not exhaustive.

**Recommendation:** Add CI first. Then add `bloc_test` for new BLoCs (don’t rewrite the existing suite). One integration test for “create invoice while offline → queue → come online” would lock the product’s core promise.

---

## 7. Accessibility

### What works

- `VanActionTile` wraps the control in `Semantics(button: true, label: title, hint: subtitle)` and has a widget test.
- Dashboard drawer and app bar add a couple of `Semantics` nodes.
- Theme contrast (indigo on slate / white) is generally in range; status is also labelled with text (`StatusPill`, extra badge labels), not color alone.
- Form fields use `InputDecoration` labels (screen readers get *something*).

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| High | Only **3** production files use `Semantics` / `semanticLabel` / `ExcludeSemantics` / `MergeSemantics` | `van_action_tile.dart`, `dashboard_drawer.dart`, `dashboard_app_bar.dart` |
| High | Logo has no `semanticLabel` | `app_logo.dart` |
| Medium | No audit of 48×48 tap targets on dense report tables / line-item steppers | `sortable_report_scaffold.dart` sort icons are 14 px |
| Medium | Hardcoded English means TalkBack cannot be localized | see §13 |
| Low | Disabled tiles use `Opacity` rather than `IgnorePointer` + visual token; semantics `enabled: false` is set, which is correct | |

This is a van-sales field app (often outdoor, often one-handed). TalkBack and large-text are not optional polish if the product is used by mixed literacy / gloved / bright-sun operators.

**Recommendation:** Add `semanticLabel` on the logo and every icon-only `IconButton`. Raise sort/filter hit areas to 48×48. Run Flutter’s accessibility guideline asserts in a couple of widget tests (`showSemanticsDebugger` / `meetsGuideline`).

---

## 8. Platform-specific concerns

### What works

- Android permissions match features: `INTERNET`, location, Bluetooth Classic (legacy + Android 12+), `REQUEST_INSTALL_PACKAGES` (sideload updates), `FileProvider` for PDF/share.
- `SafeArea` + `useSafeArea: true` on sheets.
- Dashboard is responsive (drawer vs sidebar via `LayoutBuilder`).
- Release signing is gated on `android/key.properties` (with an example file); the JKS is **not** in git.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | `REQUEST_INSTALL_PACKAGES` is a Play-policy-sensitive permission; fine for sideload fleets, must stay documented | `AndroidManifest.xml` |
| Medium | `minSdk` is whatever Flutter ships; `targetSdk` is 34 (behind current Play requirements over time) | `android/app/build.gradle.kts` |
| Medium | iOS / web / desktop runners exist but the product is Android-first; no deep-link intent filters | `AndroidManifest.xml` launcher-only |
| Low | `android:label="van_sales"` (package name, not “Nellon Van Sales”) | manifest |
| Low | `key.properties` and `nellon-release.jks` are untracked but **not** in `.gitignore` — easy to commit by accident | `.gitignore` |
| Low | Landscape is not locked or tested | — |

**Recommendation:** Add `android/key.properties` and `*.jks` to `.gitignore`. Decide Play vs sideload explicitly; if Play, drop `REQUEST_INSTALL_PACKAGES` and ship AAB + Play in-app updates.

---

## 9. Security

### What works

- Zoho **refresh token / client secret** go through `FlutterSecureStorage` (`LocalStorageService`).
- `ServerConfigCubit` refuses to let an empty Firestore doc wipe a working cache.
- `AppLogger` redacts OAuth-shaped strings.
- Firebase API keys in `firebase_options.dart` are the usual public client keys (expected).
- Release keystore is not committed; `key.properties.example` is.
- HTTPS to Zoho Accounts / Books (Dio default).
- License UUID stored in secure storage.
- Input is validated on forms (`GlobalKey<FormState>`, quantity caps in the line editor).

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| High | **Zoho access token is stored in plaintext Hive** `master_data_box` | `HiveDatabaseService.oauthAccessToken` / `setOauthAccessToken` |
| High | Hive boxes are **unencrypted** and hold customers, invoices, receipts, GPS, TRNs, queue payloads | `HiveDatabaseService.init` — no `HiveAesCipher` |
| Medium | No certificate pinning | `ZohoApiClient` Dio instance |
| Medium | `google-services.json` is committed (normal for Firebase, still a client identifier) | `android/app/google-services.json` |
| Medium | Logout does **not** wipe Hive business data or the access-token cache | `AuthRepository.signOut` → Firebase only; `clearAll()` exists and is unused on logout |
| Medium | OAuth refresh posts `client_secret` + `refresh_token` as **query parameters** | `zoho_api_client.dart` `_refreshAccessToken` — they also land in URL logs if a proxy is present |
| Low | No biometric gate on license / cash closing / settings | — |
| Low | `Error`/`Exception` strings from Zoho are sometimes forwarded after prefix-stripping; a Zoho body can still be technical | `error_mapper.dart` |

A stolen or shared van phone can dump Hive and replay a live access token (typically 1 hour) plus the entire customer/invoice history. Refresh-token protection is necessary but not sufficient.

**Recommendation:** Store the access token in `FlutterSecureStorage` (same service as the refresh token). Encrypt Hive or stop persisting PII/tokens in plaintext. Call a coordinated wipe (Hive + secure storage + queues) on logout after cash-closing. Move OAuth fields to a POST body.

---

## 10. Package / dependency review

| Package | Role | Notes |
|---------|------|--------|
| `flutter_bloc` / `bloc` ^9 | State | Current, appropriate |
| `get_it` ^9 | DI | Fine; don’t scatter `sl<>` in widgets |
| `hive` ^2.2.3 | Local DB | Hive 2 is maintenance-mode; consider `hive_ce` or `isar`/`drift` if you outgrow JSON boxes |
| `hive_generator` | Unused | Remove or use |
| `dio` ^5 | HTTP | Fine |
| `firebase_*` (core 4, auth 6, firestore 6, crashlytics 5) | Auth + config + crashes | Current major line |
| `flutter_secure_storage` ^10 | Secrets | Correct choice |
| `geolocator` / `permission_handler` | GPS | Fine |
| `print_bluetooth_thermal` / `esc_pos_utils_plus` | ESC/POS | Niche; pin and smoke-test on the Nigachi device |
| `fl_chart` | One dashboard chart | Acceptable |
| `flutter_lints` ^6 | Analysis | Too loose for this codebase (see §15) |
| `equatable` | Value equality | Consistent |

No `dependency_overrides`. Not a monorepo. Caret syntax is used throughout.

**Recommendation:** Run `flutter pub outdated` on a cadence. Delete `hive_generator` until you actually generate adapters.

---

## 11. Navigation and routing

### What works

- One style: imperative `Navigator.push` / `showModalBottomSheet` / `showDialog`. No half-migrated `go_router`.
- Route **arguments are typed widgets** (`SalesInvoiceEditorPage(invoice: …)`), not `Map<String, dynamic>`.
- Auth / license / masters / update gates are centralized (`AppUpdateGate` → `SessionGateway` → `LicenseGate`).
- Dashboard navigation is collected in `DashboardNavHelpers` (one place to find pushes).

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | No named routes / route constants; every feature hard-codes `Navigator.push(MaterialPageRoute(...))` | `dashboard_navigation_helpers.dart` (~400+ lines of push helpers) |
| Medium | Navigation is not unit-testable as a graph (you must pump widgets) | |
| Medium | No deep links (Android/iOS) | Manifest has only LAUNCHER |
| Low | `home:` on `MaterialApp` instead of a router makes back-stack and “open invoice from notification” harder later | `app.dart` |

For a single-activity van app this is acceptable. Do **not** introduce `go_router` unless you need deep links or web.

**Recommendation:** Keep imperative navigation. If the helper file keeps growing, split it per feature (`openInvoiceEditor`, `openStockTransferList`) rather than one 400-line static class.

---

## 12. Error handling

### What works

- `FlutterError.onError` and `PlatformDispatcher.instance.onError` both forward to Crashlytics (`main.dart`).
- `AppLogger.setUserIdentifier` exists for attaching a user to reports.
- `userFacingMessage()` maps `DioException`, timeouts, sockets, stock errors, and strips `DioException:` prefixes.
- Sync classifies `[Retryable]` vs `[Needs Attention]` (documented in `CLAUDE.md`; covered by `error_classification_test.dart`).
- Offline enqueue is the product’s core graceful-degradation path.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | Firebase init failure is only logged — Crashlytics hooks never install, and the app continues | `main.dart` `catch (e)` around `Firebase.initializeApp` |
| Medium | No `runZonedGuarded` around `runApp` (partially redundant with `PlatformDispatcher.onError`, still the documented belt-and-suspenders) | `main.dart` |
| Medium | No `ErrorWidget.builder` — a build failure in release is still the red/grey error box | |
| Medium | No `BlocObserver` forwarding BLoC errors to Crashlytics | |
| Medium | Broad catches in `ZohoApiClient` wrap everything as `Exception('… $e')`, losing type information before `error_mapper` sees it | `_refreshAccessToken` |
| Low | Some snackbars still interpolate raw state messages | `sales_return_dialog.dart` success string |

**Recommendation:** Install Crashlytics hooks even if Firebase init is retried. Add a release `ErrorWidget.builder`. A 15-line `AppBlocObserver` that `AppLogger.error`s `onError` is cheap and high value.

---

## 13. Internationalization

`l10n.yaml` + `lib/l10n/app_en.arb` + generated `AppLocalizations` exist. `pubspec.yaml` has `flutter: generate: true` and `flutter_localizations`.

**None of it is wired.**

- `MaterialApp` in `app.dart` does not set `localizationsDelegates` or `supportedLocales`.
- **Zero** call sites of `AppLocalizations.of(context)` outside the generated files.
- ARB has ~15 keys (title, login, sync labels). The UI has hundreds of hardcoded English strings.
- Currency *is* org-aware (`context.org`, `formatCurrency`) — good — but dates use `DateFormat` without an explicit locale from l10n.
- Only `en` exists. RTL is untested.

This is the largest “we started the checklist item and stopped” gap in the repo.

**Recommendation:** Either (a) wire delegates now and migrate strings screen-by-screen starting with login / errors / dashboard, or (b) delete the unused l10n surface so it does not rot. Do not add a second locale until the first is actually used.

---

## 14. Dependency injection

### What works

- `setupDependencyInjection()` has a documented, correct order: Hive → Firebase auth → Zoho → document numbers → sync worker → repositories → license/device → PDF/thermal.
- Repositories are registered against **interfaces**.
- `app.dart` re-exposes them as `RepositoryProvider` so widgets use `context.read<InvoiceRepository>()`.
- Lifetimes are all lazy singletons except the eagerly initialized Hive service.
- `unawaited(voucherPdfService.clearStaleTempFiles())` is an explicit fire-and-forget.

### Gaps

| Severity | Finding | Evidence |
|----------|---------|----------|
| Medium | Service locator is used **inside** UI and BLoCs, not only at the composition root | `invoice_flow_sheet.dart` `sl<DocumentNumberService>()`; `auth_bloc.dart` `sl`; `SessionGateway` `sl<HiveDatabaseService>()`; `open_ledger_transaction.dart` `sl<InvoiceRepository>()`; `logout.dart` `sl<CashClosingRepository>()`; `customer_selector_sheet.dart` `sl<>` |
| Medium | UI cubits depend on `HiveDatabaseService` (concrete data type) | `OrganizationCubit`, `SalespersonCubit` |
| Medium | No environment-specific bindings (dev/staging/prod). One Firebase project, one Zoho org injected at runtime from Firestore | Same finding as enterprise H5 — still true |
| Low | `VoucherPdfService` / `ThermalPrinterService` registered twice (as self and as the repository interface) — fine, but easy to resolve the concrete type from UI | |

GetIt at the composition root is the right pattern. GetIt inside feature widgets re-introduces the hidden graph the `RepositoryProvider` layer was meant to avoid.

**Recommendation:** Ban new `sl<>` calls outside `injection.dart` and `app.dart`. Pass `DocumentNumberService` through `RepositoryProvider` or the editor BLoC constructor (several editors already accept it).

---

## 15. Static analysis

```yaml
# analysis_options.yaml today
include: package:flutter_lints/flutter.yaml
analyzer:
  exclude: [scratch/**, test/test_org_sync.dart]
linter:
  rules:
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
```

Missing versus the checklist:

| Setting / rule | Present? |
|----------------|----------|
| `strict-casts` / `strict-inference` / `strict-raw-types` | No |
| `very_good_analysis` or equivalent strict set | No |
| `avoid_print` | Inherited from flutter_lints (and the code complies) |
| `unawaited_futures` | Not enabled |
| `prefer_final_locals` | Not enabled |
| `always_declare_return_types` | Not enabled |
| `avoid_catches_without_on_clauses` | Not enabled |
| `always_use_package_imports` | Not enabled |
| `flutter analyze` in CI | No CI |
| Lint suppressions justified | Partial — unused-field ignores explain *why*, file-level `prefer_initializing_formals` does not |

**Recommendation:** Turn on the three strict analyzer flags on a branch and fix what breaks (expect `Map<String, dynamic>` JSON code to need work). Add `always_use_package_imports`, `unawaited_futures`, and `avoid_catches_without_on_clauses` next. Treat analyzer warnings as CI failures.

---

## Architecture deep-dives

### Domain → data leak (highest structural debt)

```dart
// lib/domain/repositories/sync_repository.dart
import '../../data/models/sync_queue_item.dart';
import '../../data/services/sync_worker.dart'; // MasterType
```

Every transaction repository interface that returns or accepts a queue item has the same import. `CLAUDE.md` says “`domain/` knows nothing about `data/`.” The compiler currently allows UI to import Hive models via the domain barrel.

**Fix:** Move `SyncQueueItem` (or a domain `SyncWorkItem`) and `MasterType` under `lib/domain/`. Keep Hive-specific serialization on a data DTO if needed.

### God services

| File | Lines | Role |
|------|------:|------|
| `hive_database_service.dart` | ~1,873 | Every box, every entity, stock adjustments, OAuth cache, update channel, cash-closing, UOM |
| `zoho_api_client.dart` | ~1,684 | OAuth + every Books/Inventory endpoint + paging |
| `sync_worker.dart` | ~1,103 | Queue, dispatch, retry, ID rewrite, stock assert, connectivity timer |
| `stock_transfer_bloc.dart` | ~829 | Entire planning-grid editor |

These files work, and they have tests, but they are where regressions hide. Split along the seams you already named in docs (`sales-repository-split-plan.md` was done; do the same for Hive: `HiveMasterStore`, `HiveHistoryStore`, `HiveSyncQueue`).

### Unused BLoC dependencies

Several editor/list BLoCs still require repositories they no longer use, with `// ignore: unused_field — kept so existing BlocProvider wiring stays unchanged`. That freezes a lie into the constructor and makes tests harder. Update the `BlocProvider` and delete the fields.

---

## Progress since previous reviews

| Earlier finding | Status now |
|-----------------|------------|
| No Crashlytics / only `print` (H2, June) | **Fixed** — Crashlytics + `AppLogger`, zero `print` in `lib/` |
| ~5 test files, 2 BLoCs tested (H3) | **Mostly fixed** — 104 test files, list/editor BLoCs covered |
| Mixed list+editor BLoCs (July) | **Fixed** for invoice/order/receipt/return/expense; stock-transfer editor still app-scoped |
| No in-app update (M8) | **Fixed** — `AppUpdateGate` + Firestore version + sideload |
| No localization (L1) | **Scaffold only** — ARB unused |
| Baseline lints (L4) | **Unchanged** |
| Hive unencrypted / no schema version (H4) | **Unchanged** |
| Logout does not wipe (H6) | **Unchanged** |
| No CI / flavors (H5) | **Unchanged** |
| No certificate pinning (M1) | **Unchanged** |
| Shared widgets duplicated (July) | **Fixed** — `ui/core/widgets` is real |
| `context.mounted` after await | **Fixed** in the paths inspected |

---

## Prioritized recommendations

### P0 — do before the next fleet build

1. **Move `SyncQueueItem` + `MasterType` into `domain/`** so the architecture rule is true again.
2. **Stop storing the Zoho access token in Hive.** Use `FlutterSecureStorage`.
3. **Add `*.jks` and `android/key.properties` to `.gitignore`.**
4. **Add CI:** `flutter analyze` + `flutter test`. Fail the build on issues.
5. **Wipe or isolate local data on logout** (after cash-closing), including the access-token cache.

### P1 — next hardening sprint

6. Enable `strict-casts`, `strict-inference`, `strict-raw-types`.
7. Replace blanket `catch (e)` in `ZohoApiClient` / `SyncWorker` with typed catches; don’t catch `Error`.
8. Provide `StockTransferBloc` only on the editor route; delete unused BLoC constructor fields.
9. Wire `AppLocalizations` into `MaterialApp` and migrate login + error + dashboard strings.
10. Encrypt Hive or document why a rooted van phone is an accepted risk.
11. Ban new `sl<>` outside the composition root.

### P2 — quality / UX

12. Extract the largest `_build*` helpers; drop `isDark` parameters in favor of `Theme`.
13. Migrate remaining list states to the invoice `status` enum.
14. Semantics pass on icon buttons, logo, report sort headers (48×48).
15. One offline→online invoice integration test.
16. `ErrorWidget.builder` + `BlocObserver`.
17. Remove unused `hive_generator` (or generate real adapters and add a schema version).

---

## Checklist snapshot

Copied from the review skill, marked against this repo.

**1. Project health**  
[x] Consistent folder structure  
[x] Layer separation (with one serious leak — §1)  
[ ] No business logic in widgets (`invoice_flow_sheet` still orchestrates)  
[x] pubspec mostly clean (`hive_generator` unused)  
[ ] Strict analysis_options  
[x] No `print()` in production  
[x] Generated Hive adapters N/A (JSON boxes); l10n generated files committed  
[x] Platform code behind services  

**2. Dart**  
[ ] Strict casts/inference/raw types  
[ ] Limited `!`  
[ ] Typed catches / no catching `Error`  
[x] `late` mostly justified  
[x] Futures awaited or `unawaited`  
[ ] Package imports  
[ ] Unmodifiable collections at API boundaries  
[x] Some Dart 3 pattern matching; not widespread  
[x] No `print()`  

**3. Widgets**  
[ ] `build()` methods kept small  
[ ] `_build*` extracted to widgets  
[x] `const` encouraged  
[x] `ValueKey` on lists; `GlobalKey` only on forms  
[ ] Colors/text from theme everywhere  
[x] No I/O in `build()` (except a full `getItems()` read)  

**4. State**  
[x] Logic in BLoCs  
[x] Deps injected (except leftover `sl<>`)  
[x] Repository layer  
[ ] No god managers (`HiveDatabaseService`, `StockTransferBloc` app-scoped)  
[ ] BLoCs do not take other BLoCs (pages do coordinate several)  
[x] Immutable Equatable states  
[ ] Sealed / status enums everywhere (invoice yes; several lists no)  
[x] `mounted` / `context.mounted` after async  
[x] Feature editor BLoCs generally disposed; stock-transfer editor is not  

**5. Performance**  
[x] `ListView.builder`/`separated` for real lists  
[ ] Pagination  
[x] Specific `MediaQuery.*Of`  
[ ] Image `cacheWidth`  

**6. Testing**  
[x] Unit tests for business logic  
[x] Some widget tests  
[ ] Meaningful integration / golden  
[ ] CI gate  
[ ] `bloc_test`  

**7. Accessibility**  
[ ] Semantics coverage  
[ ] 48×48 targets  
[x] Status not color-only on document cards  

**8. Platform**  
[x] Android permissions match features  
[x] `SafeArea`  
[ ] Keystore gitignored  
[ ] Responsive breakpoints formalized beyond dashboard  

**9. Security**  
[x] Refresh token in secure storage  
[ ] Access token + Hive encrypted  
[ ] No secrets in git (keystore ok; add gitignore)  
[ ] HTTPS pinning  
[x] Form validation  

**10. Packages**  
[x] Caret versions, no overrides  
[ ] Unused generator removed  

**11. Navigation**  
[x] One approach, typed args  
[ ] Central route table / deep links  

**12. Errors**  
[x] Crashlytics + framework hooks  
[ ] `ErrorWidget.builder` / `BlocObserver` / zone  
[x] User-facing mapper + offline queue  

**13. l10n**  
[ ] Delegates wired  
[ ] Strings migrated  
[x] Currency from org  

**14. DI**  
[x] Interfaces at boundaries  
[ ] `sl<>` only at composition root  
[ ] Env-specific bindings  

**15. Analysis**  
[ ] Strict flags  
[ ] Strict lint set  
[ ] CI analyze  

---

## Suggested review follow-ups

These are optional next artifacts, not part of this report:

- A short ADR: “Hive JSON boxes vs typed adapters vs Drift.”
- A one-page threat model for a lost van phone (Hive dump, Bluetooth, sideload).
- `flutter analyze` + `flutter test --coverage` numbers attached to the P1 sprint.

---

*End of report.*
