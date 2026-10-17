# MIS reports: from runs to custom date ranges — task list

Goal: every report (Margin, Purchases, P&L, Executive Summary, BS, TB) is viewed for **any From/To dates**,
across everything ever fetched, instead of one stored run at a time.

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

## Decisions to confirm (defaults assumed below)

1. **Financials grain = calendar month** (default). Day-precise P&L is Phase 4, optional.
2. **Fetch button in the web UI** calls Zoho from the server (Phase 3). Default: build it behind
   `web_auth` and a `MIS_WEB_SYNC=1` env switch, off until approved; CLI sync works regardless.
3. **Old runs** stay readable during rollout; `report_runs` becomes a fetch log after Phase 2.

---

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
- Keep the old run tables untouched until Phase 2 cleanup.

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
- Keep the `run_id` variants working until Phase 2 cleanup (branch on which param is present).

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

## Phase 2 — Financials by month range

### T2.1 GL store (`reports/db.py`)
```sql
CREATE TABLE gl_monthly (
  account_id VARCHAR(40), month CHAR(7),       -- '0000-00' = baseline: all movement before the first FY synced
  debit DECIMAL(18,2), credit DECIMAL(18,2), net DECIMAL(18,2),
  synced_at DATETIME, PRIMARY KEY (account_id, month), KEY ix_gl_month (month)
);
```
- Baseline cut-off must be a **fiscal-year start** (e.g. 2026-04-01) so P&L reset maths needs no
  per-account split: prior-year P&L = Σ baseline P&L nets → synthetic
  `__prior_years_pl__` row (same as `monthly_trial_balance.RETAINED_ID`).

### T2.2 GL sync (`reports/monthly_trial_balance.py`, `main.py`)
- `main.py gl-sync --from-month 2026-04 --to-month 2026-10 [--baseline]`:
  one `_movement()` call per month (+1 for the baseline) → upsert `gl_monthly`, record
  `sync_coverage('gl', …)`.
- Current month is always re-fetchable (Zoho keeps posting); coverage `synced_at` shows staleness.
- `financials` command keeps working (writes files), but its DB save calls `gl-sync` logic.

### T2.3 TB assembly on request (`reports/db.py`)
`build_trial_balance(from_month, to_month)`:
- opening = baseline + Σ months before `from_month` (P&L accounts: only months since the FY start
  of `from_month`; earlier P&L folds into the retained row) — port the logic from
  `generate_monthly_trial_balance` into a pure function shared by both paths.
- account metadata + categories from `category_master` table + `output/coa_snapshot.json`
  → **category overrides apply immediately** (today they are frozen in the run).
- Refuse (400) when months between baseline and `to_month` are missing: “GL not loaded for Jul-26”.

### T2.4 Statements on request
- `/api/statement?from=2026-04&to=2026-09&name=PL` → `financials.build_financials(tb_rows, summary)`,
  return `{columns, lines, tree}` in today's shape. Outer span includes comparison periods; the
  client keeps aggregating months → periods (flow vs balance) exactly as now.
- `/api/tb?from=&to=` likewise. Drop `statement_lines` / `statement_values` writes.
- Cache built statements in-process keyed by `(from, to, max(gl.synced_at), category_master.updated_at)`.

### T2.5 Migration + parity check
- Seed `gl_monthly` from run #1: `tb_monthly` → monthly `net` (debit/credit unknown → store net,
  flag `split_known=0`); `tb_accounts.opening` → baseline for BS accounts; retained row → baseline.
- Parity test: TB/PL/BS rebuilt for Apr–Sep from `gl_monthly` == run #1 `statement_values`
  to the cent.
- Recommended after approval: `gl-sync --from-month 2026-04 --to-month 2026-10 --baseline`
  (~8 GL calls) to get real Dr/Cr splits and October.

### T2.6 Excel export (`reports/excel_export.py`, `server.py`)
- `build_workbook(from, to)`; margin/purchases sheets come from the date tables for the same range
  (removes the “matching run” guesswork). Button href: `api/export.xlsx?from=&to=`.

---

## Phase 3 — Fetch missing dates from the web (needs decision 2)

### T3.1 Sync jobs
- `sync_jobs(id, dataset, from_date, to_date, status, progress, message, requested_by, created_at,
  finished_at)`.
- `POST /api/sync {dataset, from, to}` → insert job, spawn
  `.venv/bin/python main.py sync --job <id>` (subprocess, detached); **one job at a time**
  (Zoho rate limit) — second request gets 409 with the running job.
- `GET /api/sync/<id>` → status/progress; the fetchers' `log` callbacks write progress lines.
- Guards: requires `web_auth` JWT (the site is otherwise public), `MIS_WEB_SYNC=1`, range ≤ 3 months
  per job, invoice-detail call budget shown before confirm (“~N Zoho calls”).

### T3.2 UI
- Coverage hint gets a **Fetch Oct 16 – 17** button → confirm dialog with call estimate → progress
  → reload the current tab on success.

---

## Phase 4 — Optional: day-precise financials
- For a range starting/ending mid-month: whole months from `gl_monthly`, edge partial months via
  live `_movement(start, end)` (≤ 2 calls), cached in `gl_range_cache(from_date, to_date, account_id, …)`.
- Opening for a mid-month start = month-start opening + live movement for the days before.

## Phase 5 — Cleanup
- Remove `run_id` API variants, `pickRun()`, `/api/runs` from the UI; keep `report_runs` as a fetch log.
- Drop `margin_lines`, `margin_invoices`, `purchase_lines`, `tb_accounts`, `tb_monthly`,
  `statement_lines`, `statement_values` after a backup (`backups/` dump) and one release of overlap.
- Update `README.md` and `ZOHO_API_CONTEXT.md` (new commands: `db-migrate-runs`, `db-coverage`,
  `gl-sync`, `sync`).

## Order & size

| Phase | Tasks | Zoho calls | Size |
|---|---|---|---|
| 1 | T1.1–T1.8 | none (migration from runs) | ~1–1.5 days |
| 2 | T2.1–T2.6 | none for migration; ~8 to refresh GL (needs approval) | ~1.5 days |
| 3 | T3.1–T3.2 | user-triggered | ~1 day |
| 4 | — | ≤ 2 per custom range | ~0.5 day |
| 5 | — | none | ~0.5 day |
