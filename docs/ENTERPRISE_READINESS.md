# Enterprise-Readiness Assessment — Van Sales App

> **Status:** Pilot/MVP-ready, not yet enterprise-ready.
> **Date:** 2026-06-13
> **Scope:** This report covers **High**, **Medium**, and **Low** severity gaps. Critical-severity items (credential rotation, at-rest encryption, release signing, CI/CD, API idempotency) are tracked separately and intentionally excluded here.

---

## Executive Summary

The `van_sales` app is a well-structured, offline-first Flutter application with a clean domain/data/ui separation, a working Hive-backed sync queue, and a functioning Zoho Books integration. The architecture is sound and the core happy-path flows (invoice → receipt → return → sync) work.

For a controlled pilot it is fit for purpose. For an **enterprise rollout** — many devices, many users, large master datasets, multi-week field uptime without a developer watching — it has gaps in four areas:

1. **Resilience** — the sync engine has no retry/backoff and cannot recover items stranded mid-upload by an app kill.
2. **Operability** — there is no crash reporting and no structured logging, so field failures are invisible.
3. **Confidence** — only ~2 of 10 BLoCs are tested and there is no schema-migration path, so changes are risky to ship.
4. **Scale & governance** — full datasets are loaded into memory, there is no role-based access control, and logout leaves business data on the device.

The roadmap at the end sequences these into three phases.

---

## Findings by Severity

### HIGH

| # | Finding | Evidence | Risk | Remediation |
|---|---------|----------|------|-------------|
| H1 | **Sync has no retry/backoff and no stuck-state recovery.** Failed items are marked `failed` and left in the queue; the whole queue is re-run on the next trigger with no delay or attempt cap. An item marked `syncing` just before an app kill is never reset, so it can stall forever. | `sync_worker.dart:168-176` (catch → mark failed, no retry); `:136` (mark `syncing` before upload, no recovery path) | Field transactions silently fail to reach Zoho; a crash mid-sync can permanently orphan a transaction. | Add per-item retry count + exponential backoff with a cap; classify errors (network/timeout → retry, 4xx → park for manual review, 5xx → retry); on startup, reset any `syncing` item back to `pending`. |
| H2 | **No crash reporting and no structured logging.** Errors go to `print()` only. | `sync_worker.dart:170`; `main.dart:28`; 10+ `print` sites in `zoho_api_client.dart` | Production failures are invisible — no way to know a device is failing to sync until the user complains. | Add Firebase Crashlytics; wrap `main()` in `runZonedGuarded` + set `FlutterError.onError`; replace `print` with the `logger` package at proper levels. |
| H3 | **Thin test coverage (~2/10 BLoCs).** Only `ReceiptBloc` and `LicenseCubit` are tested (5 files, ~970 lines). No `bloc_test`/`mocktail`. `ZohoApiClient`, `HiveDatabaseService`, and `SyncWorker` error paths are untested. | `test/` (5 files); `pubspec.yaml` (no mock framework) | Regressions ship undetected; refactors are high-risk. | Adopt `bloc_test` + `mocktail`; cover `AuthBloc`, `SyncBloc`, `SalesInvoiceBloc` first, then the rest; add sync retry/error-path tests. |
| H4 | **No Hive schema versioning or migration.** Models deserialize from JSON with fallback defaults; there is no version stamp on the boxes. | `hive_database_service.dart` (JSON `fromJson`, no version key) | A model field change silently corrupts or drops existing on-device data after an app update. | Stamp a schema version in `master_data_box`; add a migration step on boot that upgrades old records before use. |
| H5 | **No build flavors / environment config.** A single Firebase project and Zoho org are baked in; there is no dev/staging/prod separation. | `firebase_options.dart`; `zoho_api_client.dart` (single org) | No safe place to test against non-production data; risk of pilot traffic hitting prod books. | Add `dev`/`staging`/`prod` flavors with per-flavor config and Firebase projects. |
| H6 | **Logout does not wipe local business data.** `signOut()` only clears the Firebase session; cached customers, items, invoices, and the sync queue persist. `clearAll()` exists but is never called. | `auth_repository_impl.dart:26-28`; `firebase_auth_service.dart:34-36`; `hive_database_service.dart` (`clearAll` unused) | Account B on a shared device sees Account A's data and pending transactions. | Call `clearAll()` (and reset license/route session keys) on logout; confirm the sync queue is flushed or migrated first. |
| H7 | **No role-based access control.** Every user is hardcoded to `role: 'agent'`; no admin/supervisor distinction and no permission checks. | `firebase_auth_service.dart:49` | Cannot restrict sensitive actions (price overrides, voids, route reassignment) to authorized roles. | Source roles from Firebase custom claims or Firestore; gate sensitive UI/domain actions on role. |

### MEDIUM

| # | Finding | Evidence | Risk | Remediation |
|---|---------|----------|------|-------------|
| M1 | **No certificate pinning** on the Zoho Dio client (timeouts + interceptor only). | `zoho_api_client.dart:43-46` | MITM exposure on hostile networks. | Pin the Zoho/Firebase certs via a `HttpClientAdapter` / `badCertificateCallback`. |
| M2 | **Optimistic stock/balance updates with no rollback.** Invoices deduct stock and receipts reduce balances at save time; if sync ultimately fails, local state diverges from Zoho permanently. | `hive_database_service.dart:295-303` (stock deduction); receipt/return adjustments nearby | On-device stock and customer balances drift from the source of truth. | On terminal sync failure, reverse the local adjustment, or reconcile against a fresh master pull. |
| M3 | **Unbounded sync queue; receipt images carried as raw bytes.** Expense receipt images are held as `Uint8List` and serialized into the queue payload with no compression or size cap. | `expense_bloc.dart:65-71` (`Uint8List bytes`) | Queue storage balloons; large payloads slow or fail sync. | Compress + cap image dimensions before enqueue; set a max queue size / age policy. |
| M4 | **No pagination — full datasets loaded into memory.** Search pulls the entire customer/item list and filters in Dart; there is also an artificial 500 ms delay on every search. | `async_search_widget.dart:98-103` (full `getCustomers()`); `:93` (`Future.delayed(500ms)`) | UI lag and memory pressure at 1,000+ records; sluggish search. | Page/index queries at the repository layer; remove the artificial delay. |
| M5 | **No staleness control on master data.** Prices/taxes/items refresh only on manual sync; an invoice can be cut against outdated pricing. | `sync_worker.dart:214+` (`syncMaster` is explicit-call only) | Invoices priced on stale masters. | Add a TTL / last-synced timestamp and prompt or auto-refresh when stale. |
| M6 | **Multi-device, same-account conflicts unhandled.** No device tagging; two devices on one account both create records, resolved last-write-wins on Zoho. | `sync_worker.dart` (no device/account guard) | Duplicate or clobbered customers/invoices. | Tag records with device ID; detect/merge or warn on conflict. |
| M7 | **Android release hardening incomplete.** `minSdk` inherits the Flutter default, there are no ProGuard/R8 rules, and the pipeline brands an APK rather than producing a signed AAB. | `build.gradle.kts:25` (`minSdk = flutter.minSdkVersion`), `:33-35`, `:50-66` (APK branding) | Larger attack surface; risk of R8 reflection crashes; bypasses Play integrity. | Lock `minSdk`; add `proguard-rules.pro` (Firebase/Dio safe); ship a signed `.aab`. |
| M8 | **No in-app / force-update mechanism and no feature flags.** No Remote Config or update gate. | `pubspec.yaml` (no `in_app_update`/`firebase_remote_config`) | Cannot force-upgrade field devices off a broken build or roll features gradually. | Add force-update gate + Firebase Remote Config for flags. |

### LOW

| # | Finding | Evidence | Remediation |
|---|---------|----------|-------------|
| L1 | No localization — `intl` present but no `.arb` files; strings hardcoded English. | `pubspec.yaml` (`intl`), no `l10n/` | Add `flutter gen-l10n` + `.arb` catalogs if multi-locale is needed. |
| L2 | Partial accessibility — Semantics present in ~33 files but coverage is incomplete (no image alt text, minimal form hints). | widget tree | Audit with the accessibility scanner; fill gaps. |
| L3 | Analytics not implemented — the dashboard analytics tab is a stub. | `dashboard_page.dart` (analytics tab placeholder) | Wire Firebase Analytics events behind a flag. |
| L4 | Baseline lints only (`flutter_lints` defaults). | `analysis_options.yaml` | Adopt a stricter rule set (e.g. `very_good_analysis`) and treat warnings as errors in CI. |

---

## Prioritized Roadmap

### Phase 1 — Pre-production hardening (~2–4 weeks)
Make field failures visible and recoverable, and stop data bleeding across accounts.
- **H2** Crashlytics + `runZonedGuarded`/`FlutterError.onError` + `logger` (replace `print`).
- **H1** Sync retry with exponential backoff + attempt cap; error classification; reset stranded `syncing` items on boot.
- **H6** Wipe local business data + session keys on logout.
- **H3 (start)** Introduce `bloc_test`/`mocktail`; cover `AuthBloc`, `SyncBloc`, `SalesInvoiceBloc` and sync error paths.

### Phase 2 — Hardening & confidence (~1–2 months)
- **H5** Build flavors (dev/staging/prod) with per-flavor Firebase + Zoho config.
- **H4** Hive schema versioning + boot-time migration.
- **H3 (finish)** Complete the BLoC/service test suite.
- **H7** Role-based access control via custom claims/Firestore.
- **M4** Repository-level pagination; remove the artificial search delay.
- **M3** Image compression + size caps; queue size/age limits.
- **M7** `minSdk` lock, ProGuard/R8 rules, signed AAB pipeline.

### Phase 3 — Scale & governance (later)
- **M1** Certificate pinning.
- **M8** Force-update gate + Remote Config feature flags.
- **M6** Multi-device conflict detection/merge (device tagging).
- **M5** Master-data staleness TTL + auto-refresh.
- **M2** Rollback/reconciliation for failed optimistic updates.
- **L1–L4** Localization, accessibility audit, analytics, stricter lints.

---

## Referenced Files
- `lib/data/services/sync_worker.dart`
- `lib/data/services/hive_database_service.dart`
- `lib/data/services/zoho_api_client.dart`
- `lib/data/repositories/auth_repository_impl.dart`
- `lib/data/services/firebase_auth_service.dart`
- `lib/ui/features/expenses/bloc/expense_bloc.dart`
- `lib/ui/core/widgets/async_search_widget.dart`
- `android/app/build.gradle.kts`
- `analysis_options.yaml`, `pubspec.yaml`
