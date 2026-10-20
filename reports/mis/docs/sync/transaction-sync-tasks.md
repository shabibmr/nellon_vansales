# Transaction sync — task list

Plan: `docs/sync/transaction-sync-plan.md`. Status as of 21 Oct 2026: tasks 0–9 done except the task-7 follow-up (first customer debit note, blocked on seeing one). Core + masters + document specs + `pipeline.py` + Cost of Sales + CLI in place. Task 9 rules audit passed after two fixes (`lines_synced_at` only after `replace_lines`; sales-order list header reads `salesorder_id`/`salesorder_number`). Next: task 10 remaining FakeGateway/pipeline tests. No Zoho call.

Scope is the runs from now on. Backfill is handled separately.

Do these in order. A later task may start only after the one it depends on is done. The order is: shared code first, then the core that every module stands on, then masters and documents, then Cost of Sales, then the CLI.

Code rules (plan, Code structure): every Zoho call goes through the gateway; nothing is copied from an existing script; per-document and per-master differences are spec data; mappers are pure; modules take a `Run`.

## 0. Confirm from saved responses (no Zoho call)

- [x] From a saved `/chartofaccounts/transactions` page, confirm `transaction_id` on an `inventory_valuation_for_invoice` row is the invoice id.
- [x] Find the posting type a debit note leaves on Cost of Sales - Nellon. Until found, debit notes take the sum of their lines' own cost.
- [x] Confirm whether plain `GET /invoices` returns debit notes. Keep the skip rule either way.

Findings (21 Oct 2026, no Zoho call):

1. **`transaction_id` = invoice id.** On `output/archive/cos_raw_all.json` (Cost of Sales - Nellon / 5.1.1000, page 1), all 195 `inventory_valuation_for_invoice` rows match `entry_number` → `invoice_id` in saved invoice lists, and `transaction_id` equals that `invoice_id` on every row.
2. **Customer debit-note COS type: not found.** The only debit-named type on that account is `inventory_valuation_for_debit_notes`, and every such row (1 on the saved page; 48/48 in `gl_journals`) is a vendor credit (`KGT-VC-*`), paired with a `vendor_credit` credit on the same id. No customer debit-note JSON is cached (`output/cache/debitnotes/_list.json` is `{"invoices": []}`; zero `type=debit_note` in 1,883 invoice detail files; `debit_notes` table empty). Debit notes keep the fallback: sum of their lines' own cost, then set `cogs_synced_at`.
3. **Plain `GET /invoices` lists in the archive do not contain debit notes.** Saved date-filtered lists (`invoices_sept26_list.json`, `invoices_2026-10-13.json`, `invoices_2026-10-15.json`, `invoices_2026-09-04.json`) are all `type=invoice` (1,870 rows, zero debit-like numbers). Debit notes are listed with `filter_by=Type.DebitNote` (`zohodocs/customer-debit-notes.yml`). Keep the skip / `exclude_ids_from='debit_notes'` / detail `reroute` rules.

## 1. Schema

- [x] Add `lines_synced_at DATETIME NULL` on `sales_invoices`, `debit_notes`, `purchase_docs`, `sales_orders`, `vendor_credits`, and `vendor_payments` in `reports/db.py` and `proposal/DB-Schema-Proposed.sql`. Do not add it to `credit_notes`.
- [x] Add `cogs_synced_at DATETIME NULL` on `sales_invoices` and `debit_notes`.
- [x] Add an ALTER path so an existing database gains those columns (`CREATE TABLE IF NOT EXISTS` will not).
- [x] Add `sync_state` (`dataset` primary key, `watermark VARCHAR(40)` holding the raw Zoho text with offset, `last_run_at`).
- [x] Add `sync_pending` (`dataset`, `doc_id`, primary key on both; `modified_time`, `reason`, `last_error`, `attempts`, `first_seen`, `last_tried`). For `dataset='cogs'`, `doc_id` is the range as `YYYY-MM-DD..YYYY-MM-DD`.
- [x] Add `sales_orders` and `sales_order_lines` (invoice shape, no COGS; lines include `quantity_invoiced` and `order_discount`).
- [x] Add `vendor_credits` and `vendor_credit_lines` (vendor, optional `bill_id`, amount, no COGS). `bill_id` joins `purchase_docs` through a `kind` column fixed to `'bill'`.
- [x] Add `vendor_payments` and `vendor_payment_bills` (`bill_payment_id` primary key; a `kind` column fixed to `'bill'` so `(kind, bill_id)` can reference `purchase_docs (kind, doc_id)`).
- [x] Leave `sync_coverage` as is. It records seeder date ranges, not watermarks.

## 2. Shared code and extractions

Each extraction keeps the script's command line and output. Write the same-rows test (task 10) before moving code, and run it after.

- [x] `seed_common.py`: add `upsert_sql(table, cols, key_cols)`.
- [x] `seed_sales_from_inv.py`: delete its `connect`, `d`, `cents`, `prorate`, `table_exists`; import them from `seed_common`.
- [x] `seed_missing_sales.py`, `seed_purchases_from_cache.py`: delete `upsert_sql`; use `seed_common.upsert_sql`.
- [x] `fetch_and_seed_gl_journals.py` and `seed_missing_sales.sync_recent_gl_journals`: use `reports/account_postings.to_row` instead of their own postings mappers.
- [x] Create `zoho_sync/mapping.py` with `build_sales_lines(header, lines, units, rates)`, moved from the per-line block of `seed_missing_sales.build_invoice_rows`. It does not filter ids. The seeder keeps its own NULL-ing of unknown customer and item ids, applied after the call.
- [x] Create `zoho_sync/cogs.py` with `load_invoice_postings(store, account_id, invoice_ids)` (from `load_gl_cogs`, filtered on account and ids) and the pure `apply_cogs(status, lines, postings_total)` (from the reconcile block, using `seed_common.prorate`). `seed_missing_sales.py` imports both.
- [x] `zoho_client.py`: sign in on first request, not in `__init__`; add an `on_auth` callback; raise `ZohoHTTPError(RuntimeError)` with `status` and `code`; remove the unused `TOKEN_CACHE`. No retry here.
- [x] `reports/account_postings.fetch_pages`: take a gateway instead of creating a `ZohoClient`; send `date_start` / `date_end` instead of `date.start` / `date.end`. `run_cli` builds a live gateway, so `fetch_cost_of_sales_nellon.py` and the other callers keep working. Update the `--from-date` / `--to-date` help text.

## 3. Core of `zoho_sync/`

The package is `reports/mis/zoho_sync/`; the six master wrappers are `reports/mis/fetch_*.py`. Full layout: plan, Code structure, Where the files go.

- [x] `gateway.py` — the `Gateway` interface `get(endpoint, params) -> dict`.
  - [x] `LiveGateway(client, budget, runlog)`: sign-in on first call, counted through `on_auth`; budget before every call; retry 429 and 5xx with backoff, each retry counted; `NotFound` on 404; list and postings pages handed to `runlog`.
  - [x] `ReplayGateway(run_folder)`: answers each request from the saved page; a missing page raises.
  - [x] `FakeGateway(responses)`: fixtures keyed by endpoint and params; records the calls made.
- [x] `budget.py` — default 20 seconds between calls (3 per minute). `--max-calls`. Shared stamp file under `output/` with an exclusive lock, so the wrappers and the runner share the cap. Interval 0 in tests.
- [x] `context.py` — `Run` (gateway, store, cache, runlog, clock, mode, `run_id`, master memo). The clock is injectable.
- [x] `store.py` — the `Store` protocol (`get`, `has`, `upsert`, `replace_lines`, `replace_range`, `max_value`, `add_pending`, `list_pending`, `clear_pending`, `get_watermark`, `set_watermark`) and `MemoryStore`.
- [x] `store_db.py` — MariaDB `Store`. Upserts through `seed_common.upsert_sql`. Columns read once per table with `SHOW COLUMNS`; a mapper key that is not a column raises. Purchase docs keyed `(kind, doc_id)`. `replace_lines` and `replace_range` run in one transaction each. Imported only by the CLI and wrappers.
- [x] `cache.py` — bare resource object at `output/cache/{folder}/{id}.json`. Atomic `.tmp` replace. Reader accepts an old envelope for one release. `is_current(folder, id, last_modified_time)`.
- [x] `runlog.py` — `output/runs/{run_id}/{dataset}/page-N.json` for every list and postings page, plus `summary.json` (calls, rows stored, pending, watermark before and after). `run_id` is `YYYYMMDD-HHMMSS` Asia/Dubai. Delete run folders older than 30 days at the start of a run.
- [x] `watermark.py` — read and write through the store. Encode `+` as `%2B`. Never add a second. Refuse a dataset with no watermark. `seed(run)`: set each dataset from `store.max_value(header_table, 'last_modified_time')`.

## 4. Masters

- [x] `masters.py` — `MasterSpec` (`kind`, `lookup` id / list / id-else-list, `path`, `list_path`, `response_key`, `type_check`, `table`, `mapper`, `deps`, `cache_folder`, `update_cols`) and `ensure(run, kind, id)` with the six steps in the plan. Raises on failure, `NotFound` on 404, `WrongType` on a type mismatch.
- [x] Six specs: customer, vendor, item (deps: `account_id`, `purchase_account_id`), account (deps: `parent_account_id`; update columns are Zoho columns only), location (list), salesperson (id, else list).
- [x] Mappers for the six, pure, in `mapping.py`. Item mapper writes `items` and `item_units` rows from the detail payload. No `raw_json` on items.
- [x] Six wrappers, `fetch_customer.py`, `fetch_vendor.py`, `fetch_item.py`, `fetch_account.py`, `fetch_location.py`, `fetch_salesperson.py`: parse the id, build a live `Run`, call `ensure`, exit non-zero on any raise. No other logic. Each refuses to call Zoho without `--yes-live`.

## 5. Document specs and mappers

- [x] `specs.py` — seven `DocSpec`s with the fields in the plan, in run order: debit notes, invoices, bills, vendor credits, sales orders, purchase orders, vendor payments.
- [x] Invoice spec: `exclude_ids_from='debit_notes'` and the `reroute` hook for a detail whose `type` is a debit note. Debit-note spec: `list_params` with `filter_by=Type.DebitNote`.
- [x] `doc_refs`: debit note `reference_invoice_id` → invoices; vendor credit `bill_id` and vendor payment `bills[].bill_id` → bills (`kind='bill'`).
- [x] Mappers per spec in `mapping.py`: `header_from_list`, `from_detail`, `collect_ids`. Invoices and debit notes use `build_sales_lines`. Vendor payment `from_detail` returns `bills[]` rows keyed by `bill_payment_id`.

## 6. Pipeline

- [x] `pipeline.py` — one loop over the specs, reading every difference from the spec:
  1. Retry `sync_pending` for the dataset.
  2. List from the watermark, every page.
  3. Per row: skip excluded ids; require `party`; `ensure` each optional id from `collect_ids`; load `doc_refs` documents through the same loop; upsert the header from `header_from_list`.
  4. Detail (skipped when `cache.is_current`); `ensure` the detail's ids; header patch and `replace_lines`; set `lines_synced_at`.
  5. Any raise puts the document in `sync_pending` with the error and moves on.
  6. When the whole list was read, move the watermark to the highest timestamp seen.

Done 21 Oct 2026, 0 Zoho calls. `zoho_sync/pipeline.py`: `run_all` / `sync_dataset`; pending retry; list with `encode_watermark` (`+` → `%2B`); exclude/`reroute`; party required; `ensure` + doc-ref load; cache-current detail skip; `lines_synced_at`; partial list (`BudgetExceeded` / error) leaves watermark; finished list moves to highest raw `last_modified_time` even with pending docs. Task 10 pipeline FakeGateway tests still open.

## 7. Cost of Sales

- [x] `ranges.py` — pure: dates from this run's stored invoices (not debit notes; see task 0 finding 2), the trailing window when the clock says 02:00 run, D to today for each changed bill on that run, and pending ranges; merged into continuous ranges.
- [x] `postings.py` — for each range, every page through `account_postings.fetch_pages` with the run's gateway, mapped with `account_postings.to_row` (`raw_json` NULL), then `store.replace_range`. A failed range goes to `sync_pending` with `dataset='cogs'`.
- [x] Wire `cogs.load_invoice_postings` and `cogs.apply_cogs` to write header and line COGS and `cogs_synced_at` per the plan's table, for invoices dated in a pulled range. Match only `transaction_type='inventory_valuation_for_invoice'` on `transaction_id`. (`cogs.write_invoice_cogs`.)
- [x] Debit notes stored this run: header COGS is the sum of their lines' own cost (0 for draft or void), line COGS unchanged, `cogs_synced_at` set. No postings pull is needed for them. Never match `inventory_valuation_for_debit_notes` rows to a customer debit note; on this account that type belongs to vendor credits (`KGT-VC-*`). (`cogs.write_debit_note_cogs`.)
- [ ] Follow-up once the first customer debit note is stored: look in that date's pulled Cost of Sales postings for a row whose `transaction_id` is the debit note id, note its `transaction_type` under task 0, and only then switch debit notes to the postings path.

## 8. CLI

- [x] `__main__.py` — `run` (`--yes-live`, `--max-calls`, `--replay RUN_ID`), `fetch KIND ID`, `seed-watermarks`. Builds the `Run`: `LiveGateway` only with `--yes-live`, `ReplayGateway` for `--replay`; otherwise it refuses any call. Pending is always retried.

Done 21 Oct 2026, 0 Zoho calls. `zoho_sync/__main__.py`: `python -m zoho_sync run|fetch|seed-watermarks`. Live refuses without `--yes-live`; `--replay` uses `ReplayGateway` on `output/runs/RUN_ID` and a fresh runlog folder; `fetch` reuses `masters.build_live_run` + `ensure`; `seed-watermarks` seeds from each `DocSpec.header_table` max `last_modified_time` (DB only). COS is now wired into `run_all` (`pipeline.run_cost_of_sales`, task 7).

## 9. Rules the pipeline must keep

Done 21 Oct 2026, 0 Zoho calls. Code audit of `pipeline.py` / `specs.py` / `watermark.py` / `mapping.py` / `cogs.py` / `postings.py` / `ranges.py`. Two gaps fixed: (1) `lines_synced_at` was set before `replace_lines` — now only after lines (or `vendor_payment_bills`) write; (2) `header_from_list_sales_order` read Zoho `invoice_id`/`invoice_number` — now reads `salesorder_id`/`salesorder_number` (debit notes still map Zoho `invoice_*` → `debit_note_*`). Existing unittest suite: 77 OK.

- [x] Debit notes run first and their ids are skipped by the invoice pass. A row already on `debit_notes` is skipped too. Detail `type` is checked before any line is written. Debit list sends `filter_by=Type.DebitNote`.
- [x] Pass the stored watermark as raw Zoho text, `+` as `%2B`. Do not add one second. Bills and the four "not stated" lists overlap on equals; a matching timestamp is a no-op.
- [x] A partial list (stopped by `--max-calls` or an error) does not move that dataset's watermark. A failed document does not hold the watermark back; it stays in `sync_pending`.
- [x] Required before a write: `customer_id` or `vendor_id`. Optional and NULL when blank: header `salesperson_id` (sales only) and `location_id`; line `item_id`, `location_id`, `account_id`. A filled-in id whose `ensure` fails or 404s stores nothing; after 3 attempts it is in the run summary.
- [x] Debit note `reference_invoice_id`, when set, must exist on `sales_invoices` (load that invoice first). Vendor payment and vendor credit `bill_id` must exist on `purchase_docs` as a bill (load that bill first).
- [x] Header from the list row only. Detail-only amounts wait for the detail step. `net_sales` is computed at detail time. `cogs` is written only by the Cost of Sales pass.
- [x] Draft and void are stored. Their COGS is 0.
- [x] A failed postings pull keeps the stored COGS, leaves `cogs_synced_at` as it was, and records the range in `sync_pending`. A posted invoice with no postings takes the sum of its lines' own cost and sets `cogs_synced_at`.
- [x] Mark `lines_synced_at` only when lines (or `vendor_payment_bills`) are written.

## 10. Tests

`tests/test_zoho_sync.py` and `tests/test_seed_extractions.py`, with fixtures in `tests/fixtures/zoho_sync/` trimmed from saved responses. No network, no database, `FakeGateway` and `MemoryStore`. Run from `reports/mis`: `python -m unittest tests.test_zoho_sync tests.test_seed_extractions`.

Extractions (write first, task 2):

- [x] `seed_missing_sales`, `seed_sales_from_inv`, and `seed_purchases_from_cache` build the same rows from the same cache before and after the extractions.
- [x] `account_postings.fetch_pages` sends `date_start` / `date_end` and reads every page through a `FakeGateway`.

Core:

- [x] `LiveGateway` with a stub `ZohoClient`: no call while unused; the first call signs in and the sign-in is counted; a 429 is retried; a 404 raises `NotFound`.
- [x] `store_db` rejects a mapper key that is not a column (stub column list, no database).
- [ ] `--replay` makes no network call and writes the same rows.

Masters and specs:

- [ ] Every `DocSpec` maps its fixture through its three mappers alone.
- [x] `ensure` follows each `MasterSpec`'s dependencies and makes no call for an id already stored or already in the run memo.
- [x] Customer `ensure` does not write a vendor. Vendor `ensure` does not write a customer.
- [x] Item `ensure` ensures its accounts before inserting the item.
- [x] Location uses the list and writes only the matching id.

Pipeline:

- [ ] Every list sends the stored watermark with `+` as `%2B`. A bill boundary row with an equal timestamp updates nothing.
- [ ] A run stopped by `--max-calls` partway through a list leaves that watermark unchanged. A finished list moves it even when one document is pending.
- [ ] No watermark: the dataset is refused and nothing is listed.
- [ ] A debit-note id is not inserted into `sales_invoices`, from the list or from a detail `type`.
- [ ] A missing item, customer, vendor, salesperson, location, or account id is ensured before the insert. The stored row keeps the id.
- [ ] A blank optional id is stored as NULL. A blank customer or vendor id stores nothing.
- [ ] A master that fails or 404s stores nothing, records the doc in `sync_pending`, and appears in the summary on the third attempt.
- [ ] A debit note whose reference invoice is not stored loads that invoice first.
- [ ] Lines missing from a new detail payload are deleted.
- [ ] Vendor-payment children come from `bills[]`, keyed by `bill_payment_id`, and only after that `bill_id` is on `purchase_docs`.

Cost of Sales:

- [x] Cost of Sales postings become `sales_invoices.cogs`, and line COGS sums to that total.
- [x] Postings spanning more than one page are all stored.
- [x] A posting replaced under a new `categorized_transaction_id` replaces the old row and is not counted twice.
- [ ] A changed bill dated D re-pulls Cost of Sales from D to today on the 02:00 run (injected clock). (`cost_of_sales_ranges` itself is covered by `RangesTests`; no pipeline-level test yet passes `claimed["bills"]` through `run_cost_of_sales`.)
- [x] A failed postings pull keeps the previous COGS and records the range as pending.
- [x] A posted invoice with no postings takes its lines' cost sum. A void invoice gets 0.
- [x] A debit note takes its lines' cost sum and sets `cogs_synced_at`, even when an `inventory_valuation_for_debit_notes` row on the same date is in `gl_journals` (vendor-credit fixture). Its dates alone do not trigger a postings pull.
- [ ] A vendor-credit posting on Cost of Sales is stored in `gl_journals` and changes no invoice or debit-note COGS.

## Not in this work

Backfill of older documents, credit-note polling, a full master-list sync, `gl_journals` beyond the Cost of Sales account, per-document journal calls, expenses, customer payments, a delete sweep, installing cron, any PUT to Zoho, and cutting production over to `zoho-koyson`. The retry wrappers in the backfill scripts stay until those scripts are next touched; no new retry wrapper is added.

Schedule, not installed: all seven at 02:00 Asia/Dubai with the trailing Cost of Sales window; invoices and debit notes also at 21:00 on working days with the Cost of Sales pass for that run's dates.
