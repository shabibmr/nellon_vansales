# MIS reports: from runs to custom date ranges — task list

Goal: every report (Margin, Purchases, P&L, Executive Summary, BS, TB) is viewed for **any From/To dates**
instead of one stored run at a time.

**Plan (revised 2026-10-17):**

| Report | Source |
|---|---|
| Margin, Margin by Line / Invoice, COGS per line, Purchases | MariaDB date tables (Phase 1, done) |
| Categories (account → category mapping) | MariaDB / `category_overrides.csv` (unchanged) |
| Trial Balance, P&L, Balance Sheet | **live from Zoho** (`/reports/generalledger` + `/chartofaccounts`) per request, cached |
| Executive Summary | built live from the live P&L + DB categories (no extra Zoho calls) |
| Excel export | built live for the requested range (financials live, margin/purchases from DB) |

No GL store in the DB: the old Phase 2 (`gl_monthly`) and Phase 4 (day-precise GL cache) are dropped.

## Current state (why it has to change)

| Layer | Today | Problem |
|---|---|---|
| Fetch | `main.py margin\|purchases\|financials --from-date --to-date` (CLI only) | New dates need a shell |
| Store | `report_runs` + child tables keyed by `run_id` (`margin_lines`, `margin_invoices`, `purchase_lines`, `tb_accounts`, `tb_monthly`, `statement_lines`, `statement_values`) | Runs overlap (#6/#7 = Sep twice), split (#8/#9 = Oct), no cross-run view |
| Financials | TB at month grain; statements pre-computed into `statement_values` at save time | Frozen: category overrides made later never apply; ranges limited to the run |
| API | `/api/margin`, `/api/margin-detail`, `/api/purchases`, `/api/statement`, `/api/tb`, `/api/export.xlsx` all take `run_id` | — |
| UI | `reports.js` `pickRun()` defaults to newest run per kind; `date-filter.js` slices months *inside* that run | September invisible on Margin while run #9 (Oct) is selected |

What we keep: the fetchers (`invoice_margin.MarginSource`, `purchases.PurchaseSource`,
`monthly_trial_balance._movement`), the on-disk `last_modified_time` cache, row builders
(`build_margin_rows`, `build_invoice_rows`, `build_purchase_rows`), statement builders
(`financials.build_profit_and_loss / build_executive_summary / build_balance_sheet`), and the
`date-filter.js` presets / comparison logic.

## Decisions

1. **Financials are live from Zoho** (decided 2026-10-17), any From/To date (day-precise), with a
   server-side cache. Balance Sheet and Excel export are live too.
2. **Fetch button in the web UI** for Margin/Purchases calls Zoho from the server (Phase 3). Default:
   behind `web_auth` and a `MIS_WEB_SYNC=1` env switch, off until approved; CLI sync works regardless.
3. **Old runs** stay readable during rollout; `report_runs` becomes a fetch log for margin/purchases,
   financials runs are no longer saved.
4. **Development uses recorded Zoho responses** (fixtures); live calls only with the user's approval.

---

## Status

| Task | State | Notes |
|---|---|---|
| T1.1–T1.5 | done (worktree `mis-date-range`) | table is `purchase_doc_lines`; coverage rows are trimmed, not merged, so each range keeps its own `synced_at` / `source` |
| T1.3 | done | **dual write** during rollout: `margin` / `purchases` still save a run (fetch log, Excel export) *and* replace the range in the dated tables; `db-load` does both too |
| T1.4 | done | dev DB: Sep = run #7, Oct = #9 + #8, purchases = #3 to the cent; re-run is identical |
| T1.6–T1.7 | done | day grain for Margin / Purchases, month grain unchanged for financials; comparison of a range starting on the 1st steps by months (1–17 Oct ↔ 1–17 Sep) |
| T1.9 | done | From / To always visible (editing → Custom); **Split by** Weekly (Mon–Sun) / Monthly / Quarterly / 6 months / Annual, fiscal-aligned, partial edge blocks; ≤ 40 columns; `?by=` in links. Financials (stored runs) get month-based splits only until Phase 2 makes them live |
| T1.8 | done | `tests/test_date_columns.py`, `tests/test_sync_replace.py` (`MIS_TEST_DB_NAME=nellon_mis_test`) |
| Test site | done | `https://algoray.tech/nellon/test-mis/` = static `web/` + `deploy/test-web/api.php` → `koyson-mis-test` on :8766 (dev DB, read-only); systemd unit not installed yet |
| T2.1 | done | `reports/live_financials.py`; `monthly_trial_balance` now cuts any columns into GL segments (`segments`, `Ledger`, `tb_rows`), CLI output unchanged (same rows, same call count). BS columns = balances at each column end, P&L reset per fiscal year of that end |
| T2.2 | done | in-process `GLCache` per segment; 15 min TTL (`MIS_LIVE_TTL`); refresh re-fetches only segments > 1 min old; one Zoho fetch at a time (60 s wait → 503); stale copy kept 24 h; ≤ 100 calls per view |
| T2.3 | done | `/api/config`, `/api/statement?name=&cols=`, `/api/tb?cols=`, `/api/export.xlsx?cols=` (run_id variants kept); 503 when `MIS_LIVE_FINANCIALS` ≠ 1 or busy, 502 when Zoho fails with no copy |
| T2.4 | done (not yet seen in a browser) | live financial tabs use day grain (any From/To, "Year to date" default, Split by incl. weekly); "Zoho · 10:42" + Refresh; stale banner. COGS relabel not done |
| T2.5 | done | `build_live_workbook`: live Executive Summary / PL / BS / TB + margin & purchases from the date tables, same columns as the screen. CLI `financials` still saves runs (dropped in Phase 4) |
| T2.6 | done offline | `tests/test_live_financials.py` (fake GL: P&L/BS/TB maths, FY reset, cache, refresh limit, single-flight, busy, stale, limits); parity vs run #1 to the cent with a fake Zoho rebuilt from its stored TB. Real Zoho fixtures not recorded (needs approval) |
| Live on a server | not enabled | needs approval: first real Zoho calls; test site would stop being Zoho-free |

## Phase 1 — Margin & Purchases by date (fixes "where is September")

### T1.1 New date-keyed tables (`reports/db.py` SCHEMA)
```sql
CREATE TABLE sales_invoices (            -- one row per Zoho invoice, latest fetch wins
  invoice_id VARCHAR(40) PRIMARY KEY,
  invoice_number, date DATE NOT NULL, month CHAR(7), due_date, status, customer_id, customer_name,
  salesperson_name, van, currency_code, exchange_rate, sub_total, discount_total, tax_total, total,
  balance, line_count, base_quantity, net_sales, cost_of_sales, gross_margin, flagged_lines,
  cost_source, last_modified_time DATETIME NULL, fetched_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  KEY ix_si_date (date), KEY ix_si_number (invoice_number)
);
CREATE TABLE sales_lines (
  invoice_id VARCHAR(40), line_no INT,  -- line_no restarts at 1 per invoice
  date DATE NOT NULL, month CHAR(7), …same measure/dimension columns as margin_lines…,
  PRIMARY KEY (invoice_id, line_no), KEY ix_sl_date (date), KEY ix_sl_item (item_id),
  FOREIGN KEY (invoice_id) REFERENCES sales_invoices (invoice_id) ON DELETE CASCADE
);
CREATE TABLE purchase_docs_lines (
  kind VARCHAR(20), doc_id VARCHAR(40), line_no INT,
  date DATE NOT NULL, month CHAR(7), number, vendor_name, status, item_id, item_name, sku, unit,
  quantity, rate, amount, last_modified_time DATETIME NULL,
  PRIMARY KEY (kind, doc_id, line_no), KEY ix_pdl_date (date)
);
CREATE TABLE sync_coverage (             -- which date ranges are loaded, per dataset
  dataset VARCHAR(20),                   -- 'sales' | 'purchases' | 'gl'
  from_date DATE, to_date DATE, synced_at DATETIME, source VARCHAR(20),  -- 'zoho' | 'cache' | 'migrated'
  PRIMARY KEY (dataset, from_date)
);
```
- Reuse `MARGIN_DB_COLUMNS` / `MARGIN_INVOICE_DB_COLUMNS` / `PURCHASE_DB_COLUMNS` and `_db_value`
  so column mapping stays in one place.
- Keep the old run tables untouched until Phase 4 cleanup.

### T1.2 Range-replace upsert (`reports/db.py`)
`sync_sales(from_date, to_date, invoices, rows, source)` and
`sync_purchases(from_date, to_date, rows, source, kinds)`, each in **one transaction**:
1. `DELETE FROM sales_invoices WHERE date BETWEEN %s AND %s` — the Zoho list for the range is
   authoritative, so voided/deleted invoices disappear (lines go via the cascade).
2. `DELETE … WHERE invoice_id IN (<fetched ids>)` — handles an invoice whose date moved *into* the
   range from elsewhere.
3. Insert headers, then lines with per-invoice `line_no`.
4. `_add_coverage(cur, dataset, from_date, to_date, source)` — merge overlapping/adjacent intervals.
5. Also insert a `report_runs` row (kind `margin`/`purchases`, `source`, summary) as the fetch log.

Purchases: same, scoped by `kind IN (…)` so `--kind bill` doesn't wipe purchase orders.

Edge: offline (`--offline`) runs only see the cache, which never learns about deletions → write
coverage with `source='cache'` so the UI can say so.

### T1.3 CLI wiring (`main.py`)
- `_cmd_margin` / `_cmd_purchases`: call `db.sync_sales` / `db.sync_purchases` instead of
  `save_*_run` (keep JSON/CSV/XLSX file outputs as they are).
- Fix `_db_save` message: `→ view at /reports?from=…&to=…` instead of `?run=`.
- New `db-coverage` sub-command: prints `sync_coverage` per dataset and gaps.

### T1.4 One-off migration of existing runs (no Zoho calls)
`main.py db-migrate-runs` → `db.migrate_runs_to_dated()`:
- For `margin` runs, ordered by `created_at` **ascending**, replay each run's rows through
  `sync_sales(run.from_date, run.to_date, …, source='migrated')` → newer runs overwrite older ones
  on overlap (#7 beats #6 for Sep; #9 then #8 fill Oct 1–15).
- Same for `purchases` runs.
- Lines need per-invoice renumbering: `ROW_NUMBER() OVER (PARTITION BY invoice_id ORDER BY line_no)`.
- Idempotent: re-running yields the same tables.
- Verify: `SUM(net_sales)` per month in `sales_lines` = the winning run's per-month total.

### T1.5 Read API by date (`reports/db.py` + `server.py`)
Columns are defined by the client (the date filter already knows presets and comparison periods):

```
GET /api/margin?from=2026-09-01&to=2026-10-15&dim=item&measure=net_sales
               &cols=p-1:2026-07-15:2026-08-31,2026-09:2026-09-01:2026-09-30,2026-10:2026-10-01:2026-10-15
GET /api/margin-detail?from=&to=&view=line|invoice
GET /api/purchases?from=&to=&dim=&measure=&cols=…
GET /api/coverage?dataset=sales|purchases|gl      → {ranges:[{from,to,synced_at,source}], min, max}
```
- `db.get_margin_pivot(cols, dimension, measure)`: one query over the outer span
  `GROUP BY dim, date` (daily grain is small: ~100 items × 365 days), bucket into `cols` in Python,
  plus a `Total` over the main range. Keep the current response shape
  (`columns`, `rows[].values`, `total`) so `renderPivot` barely changes.
- `gm_pct` stays a ratio of sums per column (never an average of percentages).
- Validate: ISO dates, `from <= to`, ≤ 40 cols, span ≤ 5 years → `ValueError` → 400.
- Keep the `run_id` variants working until Phase 4 cleanup (branch on which param is present).

### T1.6 Date filter by day (`web/assets/date-filter.js`)
- State becomes `{preset, from: 'YYYY-MM-DD', to: 'YYYY-MM-DD', before, after}`; bump
  localStorage key to `mis.datefilter.v2` (migrate old `YYYY-MM` values to month start/end).
- Custom inputs: `type="date"` for Margin/Purchases; financials tabs keep `type="month"`
  (`setGrain('month'|'day')`).
- Presets resolve to dates (`this_month` = 1st → today, etc.). `Full run` → **All loaded data**
  (coverage min → max).
- `layout()` emits `cols: [{key, label, from, to, kind}]`:
  - main range split at month boundaries (partial months labelled `Oct-26 (1–15)`), + `Total`;
  - comparison periods: when the range is whole months, step by month count (today's behaviour);
    otherwise step by the same number of days.
- `setSource()` takes coverage (`{min, max, ranges}`) instead of a run's month list.
- Hint line shows gaps: “Oct 16 – 17 not loaded”.

### T1.7 Reports page (`web/assets/reports.js`, `reports.html`)
- Remove the run selector and `pickRun()` for margin/purchase tabs; load
  `/api/coverage` once per dataset on start.
- `loadPivot` / detail fetch: pass `from`, `to`, `cols` from `DF.layout()`; drop the client-side
  `aggregate()` step for these tabs (server already bucketed).
- `syncUrl()` writes `?tab=&from=&to=` so a link reproduces the view.
- Empty state: “No sales loaded for Oct 16 – 17. Run `main.py margin --from-date … --to-date …`”
  (Phase 3 swaps this for a Fetch button).

### T1.8 Tests (`tests/`)
- `test_date_columns.py`: interval merge for coverage, column bucketing (partial months, day-step
  comparisons, leap years), `gm_pct` ratio-of-sums.
- `test_sync_replace.py` (MariaDB test schema via `MIS_DB_NAME=nellon_mis_test`, skipped if not
  configured): void removal, date moved into range, `--kind` scoping, migration winner order.

**Done when:** Margin shows Sep and Oct together, comparison periods work across them, totals per
month match runs #7, #9 + #8.

---

## Phase 2 — Live financials from Zoho (TB, P&L, BS, Executive Summary, Excel)

### T2.1 Live TB service (`reports/live_financials.py`, new)
`trial_balance(from_date, to_date, cols) -> (rows, columns, summary)`:
- Reuse `monthly_trial_balance` (`_movement`, opening / FY-reset / `RETAINED_ID` logic): refactor
  `generate_monthly_trial_balance` so the Zoho fetch (`_movement` per period) is separate from a
  pure `assemble_tb(opening, movements, categories, …)` — the CLI and the server share it.
- Columns follow the date filter's **Split by** (weekly / monthly / quarterly / 6 months / annual,
  partial edge blocks allowed) and comparison periods → one live `_movement(start, end)` per column
  + one opening call (`BOOKS_EPOCH → from-1`). Same `cols=key:from:to,…` contract as the dated API.
- Categories from `category_master.build_category_master(snapshot, overrides)` at request time →
  override changes apply immediately. COA snapshot: `output/coa_snapshot.json`, refreshed by the
  existing `load_coa_snapshot(refresh=…)` (no per-request `/chartofaccounts` call).
- Calls per view ≈ 1 + columns (+ pagination). Hard cap: ≤ 40 columns (`periods.MAX_COLS`, same as the
  filter), span ≤ 5 years → 400 beyond. Weekly over a year ≈ 54 calls on a cold cache.

### T2.2 Cache + throttle (`reports/live_financials.py`)
- In-process cache keyed by `(from, to, cols)` → `_movement` results, TTL **15 min**
  (`MIS_LIVE_TTL`); per-period entries so overlapping views reuse months (closed months could use a
  longer TTL, e.g. 6 h, `MIS_LIVE_CLOSED_TTL`).
- **One Zoho fetch at a time** (lock + single-flight: concurrent requests for the same key wait for
  the first). Second distinct request queues; 503 "Zoho busy, retry" after 60 s.
- **Stale fallback**: on Zoho error/timeout serve the last good result with `stale: true,
  fetched_at` → UI banner "Zoho unavailable — showing data from 10:42".
- Access token: `ZohoClient` already reuses `.zoho_token_cache.json` (50 min) — never refresh per
  request (OAuth refresh rate limit). Prod and test checkouts have separate caches → separate refreshes.
- `?refresh=1` bypasses the cache (button in UI), rate-limited to once per minute per range.

### T2.3 API (`server.py`)
```
GET /api/tb?from=2026-04-01&to=2026-10-17[&cols=…][&refresh=1]
GET /api/statement?name=PL|BS|Executive Summary&from=&to=[&cols=…][&refresh=1]
GET /api/export.xlsx?from=&to=
```
- Response keeps today's shape (`columns`, `lines`, `tree` / TB rows) + `fetched_at`, `stale`,
  `zoho_calls`. `financials.build_financials(rows, summary)` builds PL, BS, Executive Summary from
  one TB fetch (cache the built statements too).
- BS columns are balances at each column's end date; P&L / Executive Summary are period flows.
- Requires `web_auth` JWT like every `/api` route; `MIS_LIVE_FINANCIALS=1` switch (off → 503 with a
  clear message) so prod can deploy before it is enabled.
- Keep `run_id` variants until Phase 5.

### T2.4 UI (`reports.js`, `date-filter.js`)
- Financial tabs drop the run selector; date filter uses **day grain** for all tabs (`setSource`
  without months → free From/To, no coverage gaps for financials).
- Loading state ("Fetching from Zoho…", can take several seconds), `fetched_at` + **Refresh** button,
  stale banner.
- Executive Summary / P&L COGS label: "COGS (Zoho ledger)"; Margin tab: "COGS (invoice line cost)".
  Optional reconciliation line: ledger COGS − Σ line cost for the same range.

### T2.5 Excel export live (`reports/excel_export.py`)
- `build_workbook(from, to)`: Executive Summary, PL, BS, TB from T2.1 (cached), Margin / Purchases
  sheets from the date tables for the same range. Button href `api/export.xlsx?from=&to=`.
- CLI `financials` keeps writing files; it stops saving financials runs to the DB.

### T2.6 Tests (offline only)
- Record Zoho responses once (with approval) for one fiscal year → `tests/fixtures/zoho_gl/*.json`;
  a fake `ZohoClient` serves them.
- Parity: live path for Apr–Sep == run #1 `statement_values` to the cent (TB, PL, BS, Executive Summary).
- Cache: hit/miss, TTL expiry, single-flight (2 threads → 1 fetch), stale fallback on error,
  column cap → 400.

**Done when:** TB / P&L / BS / Executive Summary open for any From/To (incl. mid-month), category
overrides apply immediately, a repeat view within 15 min makes 0 Zoho calls, export matches the screen.

---

## Phase 3 — Fetch missing Margin / Purchases dates from the web (needs decision 2)

### T3.1 Sync jobs
- `sync_jobs(id, dataset, from_date, to_date, status, progress, message, requested_by, created_at,
  finished_at)`; datasets `sales`, `purchases` only (financials are live).
- `POST /api/sync {dataset, from, to}` → insert job, spawn
  `.venv/bin/python main.py sync --job <id>` (subprocess, detached); **one job at a time**
  (Zoho rate limit; shares the T2.2 lock) — second request gets 409 with the running job.
- `GET /api/sync/<id>` → status/progress; the fetchers' `log` callbacks write progress lines.
- Guards: `web_auth` JWT, `MIS_WEB_SYNC=1`, range ≤ 3 months per job, invoice-detail call budget
  shown before confirm (“~N Zoho calls”).
- CLI: `margin` / `purchases` gain `--missing-only` (fetch only coverage gaps) and keep full-range
  re-fetch as the default for picking up edits/voids.

### T3.2 UI
- Coverage hint gets a **Fetch Oct 16 – 17** button → confirm dialog with call estimate → progress
  → reload the current tab on success.

---

## Phase 4 — Cleanup
- Remove `run_id` API variants, `pickRun()`, `/api/runs` from the UI; keep `report_runs` as the
  margin/purchases fetch log.
- Drop `margin_lines`, `margin_invoices`, `purchase_lines`, `tb_accounts`, `tb_monthly`,
  `statement_lines`, `statement_values` after a backup (`backups/` dump) and one release of overlap.
- Update `README.md` and `ZOHO_API_CONTEXT.md` (new commands `db-migrate-runs`, `db-coverage`,
  `sync`; env `MIS_LIVE_FINANCIALS`, `MIS_LIVE_TTL`, `MIS_WEB_SYNC`).

## Order & size

| Phase | Tasks | Zoho calls | Size |
|---|---|---|---|
| 1 | T1.1–T1.8 (done) | none (migration from runs) | ~1–1.5 days |
| 2 | T2.1–T2.6 | per uncached view ≈ 1 + columns; fixtures recorded once (needs approval) | ~1.5–2 days |
| 3 | T3.1–T3.2 | user-triggered | ~1 day |
| 4 | — | none | ~0.5 day |
