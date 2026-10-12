# App Issues

## 1. Progress bar has no message
- **Where:** Report / PDF loading indicators (report pages and voucher PDF generation)
- **Ask:** Show a message alongside the progress indicator
- **Detail:** Context-specific text plus progress — e.g. "Generating invoice PDF…", "Loading item sales report…", with counts/percent shown where known
- **Status:** noted

## 2. Progress indicator looks boring
- **Where:** Same scope as issue #1 — report / PDF loading indicators
- **Ask:** Replace the plain spinner with a better-looking loader
- **Detail:** Modern spinner inside a styled card, with the message text from issue #1 shown in the card
- **Status:** noted

## 3. Voucher date field must not be editable
- **Where:** All transaction editors — invoice, sales order, receipt, sales return, expense, stock transfer
- **Ask:** Disable the date field everywhere
- **Detail:** Date is always the current device date, shown read-only. No override — not editable by anyone, no settings toggle, no hidden gesture.
- **Status:** noted

## 4. Share sheet for a voucher looks bland
- **Where:** The in-app share options sheet shown after tapping Share on a voucher opened from a transaction list
- **Ask:** Give it a proper design
- **Detail:** Full redesign — header, layout, and the share action items all reworked to fit the app theme
- **Status:** noted

## 5. Auto-update can loop forever
- **Where:** `AppUpdateService` / `AppUpdateCubit` / `AppUpdateInfo.fromFirestore`
- **Ask:** Stop the app from re-downloading and re-installing the same build in a loop
- **Detail:** The only guard is `latest_build_number > installed build number`. If the APK at `apk_url` was built with a lower build number than the value typed into Firestore `server_config/app_version`, the install succeeds but the local build never reaches the target, so the update prompts again on every restart. With `force_update: true` the user cannot escape the screen.
- **Fix approach:** Open — Claude to propose when implementing. Options discussed: attempt counter per build, verify the downloaded APK's build number before installing, escape hatch on the force-update screen after repeated failures.
- **Related:** Current error handling already works (red error box + "Retry Update" button); this is about the success-but-no-version-change case.
- **Status:** noted

## 6. Debug logs upload to Firestore with no way to turn it off
- **Where:** `lib/data/services/debug_file_logger.dart`, called from `main.dart`
- **Current behaviour:** Every app launch uploads the previous session's `debug_log.txt` as a document into Firestore collection `debug_logs`. Nothing gates it — `flushPreviousSessionIfAny()` runs unconditionally. Only remote workaround today is denying writes to `debug_logs` in Firestore security rules, and on failure the local file is retained and retried on every later launch, so it grows without bound.
- **Ask:** Add a remote kill switch
- **Detail:**
  - Switch lives per-device in the device's `app_licenses` document
  - Off means upload only — the local `debug_log.txt` keeps being written for on-device debugging, it just isn't sent to Firestore
  - Also fix the unbounded local file: cap its size (trim oldest lines) AND give up and delete after N failed upload attempts
- **Status:** noted

## 7. Per-device kill switch is not live
- **Where:** `lib/data/services/license_service.dart`, `LicenseCubit`, `LicenseGate`
- **Current behaviour:** A per-device kill switch already exists — the device's `app_licenses` document has `enabled` (bool) and `expiry_at`, and `LicenseGate` blocks the app when disabled or expired. But `LicenseService` reads it with a one-shot `.get()`, so flipping `enabled: false` only takes effect on the next app launch / license check, not immediately.
- **Ask:** Decide whether to make it a live Firestore listener
- **Cost note:** Firestore bills per document read, not per connection time. A listener on one doc costs 1 read to attach, then 1 read only when the doc changes (plus a re-read on reconnect after roughly 30 min offline). Idle listeners are free. For a van fleet that is a handful of reads a day against a 50k/day free tier — effectively the same cost as today's per-launch `.get()`.
- **Decision:** Deferred — live listener vs. one-shot to be decided later.
- **Status:** noted

## 8. No search in reports or voucher lists
- **Where:** All ~13 report pages (shared `sortable_report_scaffold`) and all transaction list pages — invoice, sales order, receipt, sales return, expense, stock transfer
- **Ask:** Add a search text field that filters the list
- **Detail:**
  - Matches against all fields visible in the row — document number, customer, amount, status, date
  - Narrows the existing filters: search applies on top of the current date/status filter, does not replace it
  - Local only — filters the rows already loaded on screen, no extra Zoho query
- **Suggested approach:** One shared search field added to `sortable_report_scaffold` and the list pages; case-insensitive substring match, debounced input, layered over the existing `ListFilterCubit` / date filter state.
- **Status:** noted
