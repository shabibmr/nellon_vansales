# Nellon van-sales project analysis

Date: 2026-10-12. Scope: the parent Flutter application and `reports/mis` Python tool. This is a targeted source review, not an exhaustive audit or a production deployment assessment. Application code was not changed.

## Assessment

The application has substantial business functionality and a useful repository/BLoC structure. Its strongest engineering work is in transaction dependency resolution, offline document numbering, stock validation, and business-rule tests. The highest priorities are credential exposure and synchronization correctness. The MIS tool is small and understandable, but currently accepts several incomplete or malformed inputs as successful reports.

## Project map

| Area | Responsibility | Main implementation |
| --- | --- | --- |
| Flutter app | Android-oriented van operations; invoices, sales orders, receipts, returns, expenses, stock transfers, cash closing and reports | `lib/main.dart`, `lib/app.dart`, `lib/ui/features/` |
| Domain | Business models, repository contracts and reusable rules | `lib/domain/` |
| Data | Hive persistence, repository implementations and Zoho integration | `lib/data/` |
| Authentication and device control | Firebase phone authentication, device licensing, remote configuration and updates | Auth/licensing/update features and data services |
| MIS CLI | Fetch ledger/account data and export a trial-balance-style CSV, Excel and JSON report | `reports/mis/main.py`, `zoho_client.py`, `reports/trial_balance.py`, `exporters.py` |
| Operational tooling | Zoho endpoint scripts/reference material and PowerShell build/deployment scripts | `zoho_endpoints/`, `zohodocs/`, `scripts/` |

Inventory: 379 Dart files under `lib` (61,352 lines, including generated localization files); 122 Dart files under `test`, of which 115 have `_test.dart` names; seven Python files under MIS, including a duplicated distribution script. File counts establish scale, not executed coverage.

The application declares Dart `^3.12.0` and uses flutter_bloc, GetIt, Hive, Dio, Firebase, PDF/printing and Bluetooth thermal printing. Localization currently contains an English ARB and generated English implementation.

## How transactions move

Startup initializes Firebase and telemetry, then dependency injection opens Hive before registering services and repositories. Feature BLoCs generally receive repository interfaces through providers or constructors.

Saving is online-first with an offline queue fallback. `SyncWorker.submitOrEnqueue` validates stock, checks connectivity, sends to Zoho if online, and otherwise stores a pending or failed queue entry. Queue draining orders relational parents before dependent documents, rereads persisted payloads after reference patches, applies retry backoff, and resolves temporary IDs to remote IDs.

These mechanisms are useful, but concurrency and uncertain remote commits need stronger protection. A queue is also the only durable record of an offline submission; the online path does not persist an intent before making its request.

## Findings, in priority order

### 1. P0: Zoho credentials are publicly readable under the checked-in Firestore rules

Evidence: `firestore.rules:21` permits `allow read: if true` for every `server_config` document. `LicenseService.fetchServerConfig` reads `server_config/zoho` (`lib/data/services/license_service.dart:93`), and the model/service consume its client secret and refresh token.

If these rules are deployed and the credential document is populated as designed, an unauthenticated client can read the OAuth configuration. Public app-update metadata does not require publishing integration credentials.

Action: separate public metadata from private integration configuration. Prefer a backend that holds Zoho secrets and authorizes operations for van users. Restrict private configuration immediately and rotate affected credentials after addressing exposure paths. This review did not query Firestore or establish which rules are live.

### 2. P0: Raw credentials reach file logs, console output and Firestore diagnostic uploads

Evidence: `local_storage_service.dart:61` and `:95` log raw secrets; `zoho_api_client.dart:61` logs the credential triple and `:284` logs the token-exchange parameter map. `license_service.dart` also logs the complete remote configuration map. These calls use `DebugFileLogger` directly.

`DebugFileLogger.log` (`debug_file_logger.dart:58`) clips messages but does not redact them. Its upload path sends file lines into `debug_logs`. `AppLogger.sanitize` therefore does not protect these direct callers; its current patterns also target snake_case token labels, while several callers use camelCase labels.

Action: remove secret-bearing messages, sanitize centrally at every logging sink, and test realistic field/map formats. Existing diagnostic files and stored uploads require a retention/remediation decision. Runtime log contents were not accessed.

### 3. P1: Credential persistence is unencrypted Hive

Evidence: `local_storage_service.dart:26` opens the configuration box without an encryption cipher; `:102` writes the client secret and refresh token to it. `HiveDatabaseService.init` opens the business-data boxes without encryption as well.

This differs from the August review, which describes `FlutterSecureStorage`. The current code and dependency manifest use Hive for the credential cache.

Action: migrate credentials to platform-backed secure storage and remove the old persisted copies safely. Assess encryption of customer data and queued payloads separately. Secure storage on the phone does not solve the public Firestore exposure.

### 4. P1: Concurrent queue drains can send the same transaction more than once

Evidence: `sync_worker.dart:285` tests `_isSyncing`, then awaits connectivity at `:287`, but sets the guard only at `:324`. Two callers can both pass the initial check. Queue selection includes `SyncStatus.syncing`, and the item reread falls back to an old snapshot if the item has already been removed (`:347`).

Connectivity callbacks, the periodic retry timer and manual sync create multiple entry points. With overlapping requests, both executions can dispatch an item. Duplicate-number recovery can subsequently assign a new number, so document-number rejection is not a complete idempotency mechanism.

Action: acquire the drain guard before the first await and release it in a `finally` covering all exit paths. Add a deterministic overlapping-call test proving exactly one dispatch. This is confirmed by source control flow; it was not reproduced against a running Flutter app.

### 5. P1: Online submission lacks durable intent and uncertain-commit reconciliation

Evidence: `sync_worker.dart:169` calls `_dispatchSync` before enqueueing. `_dispatchSync` performs a remote create followed by local persistence; the invoice branch is at `:473`. Exceptions during either stage are treated as submission failures and queued for another attempt.

A process exit after remote creation can leave no durable local intent. A successful remote create followed by a local write failure, or a lost response, can queue a document that already exists remotely. The duplicate-number retry path can then create another document with a fresh number.

Action: persist a submission intent before sending; track remote identity and acknowledgment separately from local completion. Reconcile uncertain commits before retrying creates or renumbering. Verify with remote-success/local-failure and lost-response tests. The failure scenarios are design risks inferred from the inspected sequence, not observed production incidents.

### 6. P1: License rules allow clients to control entitlement fields

Evidence: `firestore.rules:11` permits any authenticated user to create a license without checking its owner or field values. Updates check the existing owner but do not restrict changed fields. `license_document.dart` stores `enabled` and expiry-related entitlement data; `LicenseCubit` uses those fields to gate access.

An authenticated client can therefore create an arbitrary entitlement document or change entitlement fields on a document it owns under these rules.

Action: let trusted server/admin code control entitlement fields. Limit client writes to explicitly allowed device/login metadata, validate ownership on creation, and validate the schema with Firestore emulator tests.

### 7. P1: MIS parsing can silently produce misleading totals

Evidence: `reports/mis/reports/trial_balance.py:62` converts unparseable amounts to `0.0` and accepts non-finite floating-point values. `fetch_general_ledger` treats a missing expected response key as an empty ledger (`:59`). `main.py:61` considers equal zero gross totals balanced and returns success at `:66`.

Offline checks against the actual functions reproduced:

- `"1,234.50"` becomes `0.0`.
- `"NaN"` becomes a non-finite float.
- An unexpected report key produces zero accounts and zero debit/credit totals.
- `include_zero=True` does not add accounts that exist only in the chart of accounts.

These checks show behavior for malformed/synthetic inputs; they do not establish that Zoho currently sends those shapes.

Action: validate required response fields and amount formats; reject non-finite amounts; use decimal money arithmetic; distinguish valid empty periods from malformed results; expose imbalance and completeness in machine-readable summary/status fields. Define the intended semantics of `include_zero` and add missing COA rows if all accounts are required.

### 8. P2: MIS completeness and transport recovery are limited

Both fetch functions make one request and ignore page metadata (`trial_balance.py:43`, `:49`). A fake response containing `has_more_page=True` still produced just one request. This is a completeness risk if the selected endpoints return paginated results; actual endpoint pagination was not verified live.

`ZohoClient.get` has timeouts but no token refresh on expiry, rate-limit retry, or transient retry policy. Dates are accepted as strings without local range validation. The standalone exporter and distribution copy duplicate the implementation, including the same parsing/fetch limitations. The standalone OAuth exchange still uses query parameters, whereas the current Flutter exchange uses a form body.

Action: establish the report response/pagination contract with fixtures, implement bounded transport recovery, validate dates, and generate distribution code from one implementation. Reconcile report rows and totals against an authoritative Zoho export before treating the workbook as validated reporting output; opening/closing balance semantics were not established in this review.

### 9. P2: Layer boundaries and large services increase change risk

Domain repository interfaces import `data/models/sync_queue_item.dart`; `domain/repositories/sync_repository.dart` additionally imports the concrete sync worker for `MasterType`. Numerous UI components depend directly on data services. This contradicts the documented domain-independence rule.

The largest services contain 1,899 lines (`ZohoApiClient`), 1,876 (`HiveDatabaseService`) and 1,104 (`SyncWorker`). They combine transport, persistence, mapping, retry, stock and relationship-resolution concerns.

Action: move queue contracts and master-type definitions into the domain layer, expose service capabilities through appropriate interfaces, then split the large services along tested responsibilities. Prioritize correctness fixes before broad refactoring.

### 10. P2: Validation and documentation need a repeatable baseline

The test tree covers business rules, payload mapping, sync reference resolution, aggregators, BLoCs and widgets. No tracked GitHub Actions workflow or `integration_test/` suite was found. `test_driver/integration_test.dart` imports `integration_test`, but that package is absent from the manifest. Build and deployment scripts exist, so the absence of GitHub Actions alone does not prove that no external CI runs.

The root README remains the Flutter starter text. Detailed context exists in `CLAUDE.md` and historical reports, but the secure-storage mismatch shows why those reports must not substitute for current-code verification.

Action: document supported setup, run analyzer and unit/widget tests in CI, and add a focused transaction lifecycle integration suite. Publish executed test and coverage results instead of treating test-file counts as coverage.

## Verification performed and limits

- Parsed all seven MIS Python files successfully with Python's AST parser.
- Ran six offline behavior checks against the trial-balance implementation using a fake client/import stub. No credentials were loaded and no network requests were made.
- Verified the locally installed Dart SDK is 3.13.2, within the declared Dart constraint.
- Inspected source, repository status, manifest, rules, selected tests and historical documentation.
- Flutter analysis and tests were not run: this checkout has no `.dart_tool` dependency configuration. Full execution requires restoring dependencies and generating the necessary project configuration.
- The Python environment has `requests` and `python-dotenv`, but lacks `openpyxl`; Excel export was not run.
- Live Firebase permissions, Zoho responses, device behavior, release artifacts and production incidents were not inspected.

## Suggested order of work

1. Close credential read/logging exposure and constrain license entitlement writes.
2. Migrate credential persistence and address existing sensitive copies.
3. Serialize queue drains and reconcile uncertain remote commits.
4. Make MIS parsing/completeness explicit and reconcile fixtures against reference exports.
5. Establish an executed analyzer/test baseline, then improve layer boundaries and documentation.
