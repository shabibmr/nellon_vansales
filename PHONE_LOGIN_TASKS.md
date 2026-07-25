# Phone Login Implementation — Task Tracker

> Companion to `ZOHO_PHONE_LOGIN_DESIGN.md` (contracts B1–B7).
> Full approved plan: `C:\Users\91991\.claude\plans\i-am-creating-a-parsed-hopcroft.md`.
> Decisions: phone OTP fully replaces email login · receipt app-number → Zoho `reference_number` · payload rules apply to ALL transaction types now (incl. mocked).
>
> **Status key:** ☑ done · ☐ open · last audited against workspace 2026-07-17

## Task 1 — Foundations: normalizer, models, Hive keys ☑

- [x] Create `lib/domain/utils/phone_normalizer.dart` — `normalizePhone(raw)`: strip `[\s\-()]`; `05…`→`+9715…`; `971…`→`+971…`; `5xxxxxxxx`→`+9715…`; `+…` as-is
- [x] `lib/domain/models/session_bind_result.dart` — enum → `{notRegistered, disabled, notFullyMapped, network}`
- [x] `lib/domain/models/salesperson.dart` + `lib/data/models/salesperson_model.dart` — add `phone`, `cashAccountId`, `cashAccountName` (nullable, copyWith clear-flags, JSON round-trip)
- [x] `lib/domain/models/user.dart` — add `final String phone` (default `''`)
- [x] `lib/data/services/hive_database_service.dart` — new keys: `session_phone`, `cash_account_id`, `orders_only_mode` (bool, default false), `doc_counter_<TAG>` (INV/SO/RCT/CN); extend `clearCurrentSalesperson()` to delete all of them

## Task 2 — Phone OTP auth cutover ☑

- [x] `lib/domain/models/phone_auth_event.dart` — sealed events: `PhoneCodeSent{verificationId, resendToken}`, `PhoneAutoVerified{credential}`, `PhoneVerificationFailed{exception}`, `PhoneCodeAutoRetrievalTimeout{verificationId}`
- [x] `lib/data/services/firebase_auth_service.dart` — `startPhoneVerification(e164, {forceResendingToken})` → Stream, `signInWithSmsCode`, `signInWithPhoneCredential`; `_mapFirebaseUser` populates `phone`; delete email methods
- [x] `lib/domain/repositories/auth_repository.dart` + impl — swap to phone methods
- [x] `lib/ui/features/auth/bloc/auth_bloc.dart` — events `PhoneSubmitted/OtpSubmitted/OtpResendRequested/OtpAborted` (+internal); states `AuthCodeSent/AuthVerifyingOtp`; bind via `verifyAndBindSession(user.phone)`; B2 error strings; AppStarted migration guard (empty phone ⇒ force logout); seed counters after bind
- [x] `lib/ui/features/auth/views/login_page.dart` — two-step (phone → OTP), step from bloc state, resend 30s cooldown, "Change number"; delete dev creds/password/forgot UI
- [x] `lib/data/services/zoho_api_client.dart` — `fetchSalespersonProfiles()` (`GET /cm_salesperson_profile`, list key `module_records`, never filter by record status)
- [x] `lib/data/repositories/salesperson_repository_impl.dart` — rewrite `verifyAndBindSession(phone)` per B2: match → cf_active → notFullyMapped checks → salesperson confirm → orders-only fallback (van empty ⇒ assigned=primary, ordersOnly=true) → persist session keys
- [x] `lib/data/services/zoho_mock/zoho_mock_catalog.dart` — `GET /cm_salesperson_profile` fixture (1 full + 1 orders-only record)
- [x] **Manual**: re-download `google-services.json` → `android/app/google-services.json` (project `nellon-vansales`, includes Android OAuth client SHA-1 `7444bb2b…`)
- [x] **Manual (Firebase console)**: Phone provider enabled; SHA-1+SHA-256 fingerprints; Play Integrity API; test phone numbers

## Task 3 — Document numbering (B5) ☑

- [x] Create `lib/data/services/document_number_service.dart` — `DocType{INV,SO,RCT,CN}`; `nextNumber` (`SHB-INV-00001`, mutex, StateError on missing prefix); `seedCounters` (max(Zoho, queue, history)+1, monotonic, offline-safe); `reseedAndNext`; `counterOf`
- [x] `zoho_api_client.dart` — `fetchDocumentNumbersStartingWith({endpoint, startswithParam, numberKey, prefix})` via `_fetchAllPages` (invoices/salesorders/creditnotes + customerpayments reference_number)
- [x] `lib/data/services/injection.dart` — register after ZohoApiClient, inject into SyncWorker
- [x] Replace 7 TEMP sites: `sales_invoice_bloc.dart` (:586,:742,:899), `sales_order_bloc.dart:403`, `receipt_bloc.dart:419`, `receipt_allocation_bloc.dart:188`, `sales_return_bloc.dart:380`, `sales_return_dialog_cubit.dart:118` (stock_transfer_bloc left as-is)
- [x] `sync_worker.dart` — `_isDuplicateNumberError` (code 4062 / wording), renumber ≤2 attempts (`_renumber_attempts` payload key), patch local history record, inline retry; `seedCounters()` after full sync

## Task 4 — Payload rules (B4) ☑

- [x] `zoho_api_client.dart` — replace `_injectLocationIdIfNeeded` with `_withPrimaryHeaderLocation` (OVERWRITES header location_id = primary) + `_withSalespersonId`; apply per type (payments/expenses location-only). Van line-item stamp via `_withVanLineItemLocations` on inv/so/cn.
- [x] Add `ignore_auto_number_generation=true` query param to `syncInvoice`/`syncSalesOrder`/`syncSalesReturn` POSTs
- [x] `syncReceiptVoucher` — `reference_number` = app receipt number, `account_id` = session cash account
- [x] `_buildZohoExpensePayload` — `paid_through_account_id` = session cash account (fallback + warn)
- [x] `zoho_payload_mapper.dart` — header whitelist `salesperson_id` (inv/so/cn); line-item whitelist `location_id` (inv/so/cn); receipt root `account_id`
- [x] `hive_database_service.dart` `saveLocal*` — local header still stamps van (`assignedWarehouseId`) for stock/scoping; Zoho path overwrites header→primary + stamps van on line items (Option B). Receipts/expenses header-only at sync; transfer unchanged.
- [x] List fetches — add `salesperson_id` to `fetchInvoices`/`fetchSalesOrders`/`fetchReceipts`/`fetchSalesReturns`/`fetchOpenInvoices`

## Task 5 — Orders-only dashboard gating ☑

- [x] `van_action_tile.dart` — `enabled` flag (Opacity 0.45 + blocked handler)
- [x] `operations_tab.dart` — `ordersOnly` param; `_OpItem.enabledInOrdersOnly` (SO + Receipts + Expenses + Cash Closing + Settings)
- [x] `dashboard_page.dart` — read `ordersOnlyMode`; blocked snackbar for stock-touching actions; early-return guards on invoices/returns/stock (SO + Receipts + Expenses + Cash Closing allowed)
- [x] `client_operations_sheet.dart` — dim invoice/return tiles in orders-only mode (order + receipt stay active)

## Task 6 — Cleanup ☑

- [x] Delete email flow in **lib**: service/repo methods, bloc events/states/handlers, login UI remnants, dev creds
- [x] Delete `fetchSalespersonLocationMappings` + old `cm_salesperson_location` mock fixture + legacy enum members + email helpers in salesperson repo
- [x] Grep sweep zero hits in dart `lib/`+`test/` for: `fetchSalespersonLocationMappings|RegisterRequested|PasswordReset|AuthNeedsRegistration|signInWithEmail|cm_salesperson_location` (only intentional leftover: `TO-TEMP-` on stock transfers)
- [x] Update tests — `auth_bloc_login_gate_test` → phone OTP; integration auth fake; sales-return / mock transport / sync-id fakes for session keys + document numbers
- [x] `flutter analyze` clean on changed paths (info-level style nits only)

## Verification (end-to-end)

1. `0542891246` → OTP → dashboard as SHIHAB DEIRA; wrong code stays on OTP; resend after 30s; unknown phone → "Not registered — contact admin."
2. SUNEER (no van) → orders-only: `orders_only_mode=true`, assigned=KGT primary; SO+Receipts+Expenses+Cash Closing+Settings active; invoice/return/stock blocked
3. Offline invoice → `SHB-INV-0000N`; sync → Zoho keeps app number (KGT-IN- untouched), header = KGT `3331482000000095023` + salesperson_id, lines = van, van stock decremented
4. Receipt: `reference_number = SHB-RCT-…`, deposit "Cash In Hand - SHIHAB DEIRA"; expense paid-through same
5. Colliding number in Zoho → sync renumbers + succeeds; history patched
6. Reopen offline → still authenticated; online → silent rebind + re-seed
7. Lists show only own documents
8. analyze clean + grep sweep zero

### Remaining to close cutover

| Area | Status |
|------|--------|
| Tasks 1–6 | Done (code + Firebase console) |
| Series prefix required at bind | Done (missing `cf_series_prefix` → notFullyMapped) |
| Device smoke (manual) | Not signed off — see plan M1–M10 |
| Zoho ops (prefixes on all 10 profiles, vans, SHAFI confirm) | Admin checklist — see plan O1–O5 |
