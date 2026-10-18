# MIS on the proposed schema: plan and task register

Goal: every report reads the schema in `DB-Schema-Proposed.md` / `DB-Schema-Proposed.sql`, in the
`zoho-koyson` database. The plan is ordered for the **shortest path to working reports**: adapt the
existing code at its seams, don't rewrite it, and delete dead code last.

Supersedes the open parts of `docs/date-range-reports-tasks.md` (Phase 1 and Phase 2 there are done and
are the base for this plan; its Phase 3 and Phase 4 are replaced below).

## Scope

In scope: the **read side**. Schema creation, report queries, live financials, category editor, Excel,
UI, removal of the run-based code.

Out of scope: **loading data**. The tables are seeded by a separate loader (built in parallel or after
this plan). That covers the sync logic in `Sync_Logic.md`, the COGS rule for `sales_lines.cogs`, and
the net-sales / discount maths. The reports trust what is in the tables. See *Seeder contract* below.

## Decisions (2026-10-19)

| # | Decision |
|---|---|
| D1 | TB, P&L, BS, Executive Summary and the Excel financial sheets stay **live from Zoho** (Phase 2: `/reports/generalledger`, `GLCache`). Margin and Purchases read the database. |
| D2 | `gl_journals`: **table only**. No loader, no seed, no check; no report reads it. |
| D3 | `zoho-koyson` is the single MIS database. `sync_coverage` and the cashflow tables are created there too. |
| D4 | Run data stays in `nellon_mis` as a backup and is not copied. The run views (`run_id` API variants, run selector, run-based Excel) are removed. |
| D5 | `sync_coverage` stays. The seeder writes one row per loaded range; `/api/coverage` is unchanged. |
| D6 | Margin = **invoices only** for now. Credit / debit notes are a later task (T9.1). |
| D7 | Status is filtered at read time: Margin skips `draft`, `void`; Purchases also skips `cancelled`. |
| D8 | Margin dimensions: **Location** = `sales_lines.location_name`; **Van** = `LEFT JOIN vans`, non-van lines as `(warehouse)`. |
| D9 | `accounts` replaces `category_master`. Live financials read `pl_bs` / `category` / `sub_category` from it; the Category editor writes `source='override'` to it **and** to `category_overrides.csv` (so a reseed keeps the edit). |
| D10 | DDL lives in `reports/db.py` `SCHEMA`: the proposed tables + `sync_coverage` + cashflow. Old tables leave `SCHEMA`. |
| D11 | CLI `margin`, `purchases`, `db-load`, `db-migrate-runs`, `db-runs` are removed. `category-master` writes `accounts`. |
| D12 | The web "Fetch missing dates" button (old Phase 3) is dropped. |
| D13 | **Dev only** switches to `zoho-koyson`. Prod and the test site stay on `nellon_mis` + the deployed code until a cut-over is approved. |
| D14 | No DB tests. Unit tests cover pure SQL builders and bucketing only; `tests/test_sync_replace.py` is deleted. |

Defaults taken (no separate decision):
- `cost_of_sales` → `cogs`; gross margin = `net_sales − cogs` at read time; detail sorts by `line_item_id`;
  line detail shows `purchase_price` and `flag` instead of `cost_rate` / `cost_source`; invoice
  `line_count` = `COUNT(*)` of its lines.
- Fiscal-year month, currency and org name come from `organization`; the chart from `accounts`.
  `output/coa_snapshot.json` stops being read by financials and the editor (cashflow keeps using it,
  untouched).
- `POST /api/refresh` (pull COA from Zoho) is removed: the seeder loads `accounts`.
- CLI `financials` keeps writing files and stops saving runs.
- Labels: P&L / Executive Summary "COGS (Zoho ledger)"; Margin "COGS (invoice line cost)".

## Speed tactics

These keep the change small; each task below uses them.

1. **Copy the DDL, don't redesign it.** `SCHEMA` takes the statements from `DB-Schema-Proposed.sql`
   verbatim. The tables already exist in `zoho-koyson`, so `CREATE TABLE IF NOT EXISTS` is a no-op there.
2. **One FROM fragment per report.** `_bucketed()` / `_range_pivot()` already build the per-column SQL.
   Change their `table` argument to a FROM + WHERE fragment (joins + status filter) and keep the rest.
   Response shapes stay the same, so `reports.js` `renderPivot` is untouched.
3. **Snapshot adapter for financials.** Add `db.coa_snapshot()` that returns the same dict shape as
   `output/coa_snapshot.json` (`accounts`, `fiscal_year_start_month`, `currency_code`,
   `organization_name`), built from `accounts` + `organization`, plus a `categories` key with the
   stored MIS columns. `live_financials`, `monthly_trial_balance` and `excel_export` keep their
   signatures; `server._cached_snapshot()` just calls the adapter.
4. **Delete, don't refactor, the run code.** Once nothing calls it, remove whole functions / routes /
   commands in one pass at the end.

## Column map (old → new)

| Report field | Old (Phase 1 tables) | New |
|---|---|---|
| Margin line source | `sales_lines` | `sales_lines l JOIN sales_invoices i USING (invoice_id) LEFT JOIN vans v ON v.location_id = l.location_id` + `i.status NOT IN ('draft','void')` |
| `customer`, `salesperson` dims | `sales_lines.customer_name`, `.salesperson_name` | `i.customer_name`, `i.salesperson_name` |
| `item` dim | `item_name` | `l.item_name` |
| `van` dim | `sales_lines.van` | `CASE WHEN v.location_id IS NULL THEN '(warehouse)' ELSE l.location_name END` |
| `location` dim (new) | — | `l.location_name` |
| `cost` measure | `cost_of_sales` | `l.cogs` |
| `gross_margin` | stored column | `l.net_sales - l.cogs` |
| `flagged` | `flag <> ''` | `l.flag <> ''` |
| Line detail | `… line_no, cost_rate, cost_source` | `i.invoice_number, i.customer_name, l.location_name, …, l.purchase_price, l.cogs AS cost, l.flag` ordered `l.date, i.invoice_number, l.line_item_id` |
| Invoice detail | `sales_invoices.line_count, cost_of_sales, gross_margin, cost_source` | `COUNT(l.line_item_id)`, `i.cogs`, `i.net_sales - i.cogs`; no `cost_source` |
| Purchase line source | `purchase_doc_lines` | `purchase_lines pl JOIN purchase_docs d USING (kind, doc_id)` + `d.status NOT IN ('draft','void','cancelled')` |
| `vendor` dim | `vendor_name` | `d.vendor_name` |
| `item`, `kind` dims | `item_name`, `kind` | `pl.item_name`, `pl.kind` |
| `documents` measure | `DISTINCT CONCAT(kind,':',doc_id)` | same, on `pl.` |
| Categories | `category_master.ledger_name …` | `accounts.account_name …` (editor JSON keeps the key `ledger_name` via an alias, so `category-master.js` is unchanged) |
| Organization | `organization.raw`, `fiscal_year_start_month` VARCHAR | proposed columns; `fiscal_year_start_month` TINYINT, 1 = January |

Every date filter uses the line's own `date` column (`sales_lines.date`, `purchase_lines.date`); both are
indexed.

## Task register

Status: `todo` / `doing` / `done` / `parked`. Hours are rough estimates for one person.

### P0 — Point dev at `zoho-koyson` (critical path, ~1 h)

| ID | Task | Files | Depends | h | Status |
|---|---|---|---|---|---|
| T0.1 | Allow `-` in the database-name check (`name.replace("_","").isalnum()` rejects `zoho-koyson`); every place that names the DB already quotes it in backticks. | `reports/db.py` `init_schema` | — | 0.1 | todo |
| T0.2 | Replace `SCHEMA` with the 18 statements from `DB-Schema-Proposed.sql` + existing `sync_coverage` + the 4 cashflow tables. Remove `report_runs`, `tb_*`, `statement_*`, `margin_*`, old `purchase_lines`, `purchase_doc_lines`, `category_master`, old `organization`, old `sales_*`. Drop the `_migrate_margin` call. | `reports/db.py` | — | 0.5 | todo |
| T0.3 | Dev `.env`: `MIS_DB_NAME=zoho-koyson`. Run `main.py db-init`; confirm only `sync_coverage` + cashflow tables are new. | `.env` (dev only, D13) | T0.1, T0.2 | 0.1 | todo |
| T0.4 | Add a one-line note to `DB-Schema-Proposed.sql` header: "copy of `reports/db.py` SCHEMA; change both". | `proposal/DB-Schema-Proposed.sql` | T0.2 | 0.1 | todo |

### P1 — Margin and Purchases queries (~2 h, parallel with P2)

| ID | Task | Files | Depends | h | Status |
|---|---|---|---|---|---|
| T1.1 | `_bucketed` / `_range_pivot`: take `source` (FROM + joins) and `where` (status filter) instead of `table`; prefix `date` with the line alias. | `reports/db.py` | T0.3 | 0.5 | todo |
| T1.2 | Margin: `_MARGIN_SOURCE`, `_MARGIN_WHERE`; `MARGIN_DIMENSIONS` per the column map (add `location`); `_MARGIN_SUMS` with `cogs` and `net_sales - cogs`. | `reports/db.py` | T1.1 | 0.5 | todo |
| T1.3 | `get_margin_detail_range`: new line / invoice SQL per the column map; update `_margin_detail` column lists. | `reports/db.py` | T1.2 | 0.4 | todo |
| T1.4 | Purchases: `_PURCHASE_SOURCE`, `_PURCHASE_WHERE`, `PURCHASE_DIMENSIONS` per the column map. | `reports/db.py` | T1.1 | 0.3 | todo |
| T1.5 | `COVERAGE_DATASETS` = `{'sales','purchases'}` (drop `gl`); `get_coverage` unchanged. | `reports/db.py` | T0.3 | 0.1 | todo |

### P2 — Accounts, organization, live financials, editor (~2.5 h, parallel with P1)

| ID | Task | Files | Depends | h | Status |
|---|---|---|---|---|---|
| T2.1 | `db.get_organization()` reads the proposed columns (no `raw`); `save_organization` removed or rewritten to the proposed columns (`org-sync`). Store `fiscal_year_start_month` as 1 for Zoho's 0. | `reports/db.py`, `main.py` (`org-sync`) | T0.3 | 0.3 | todo |
| T2.2 | `db.coa_snapshot()` adapter: `accounts` rows mapped to the Zoho chart keys `build_category_master` reads (`account_id`, `account_code`, `account_name`, `account_type`, `parent_account_id`, `parent_account_name`, `is_active`; `current_balance` = 0), plus `organization_name`, `currency_code`, `fiscal_year_start_month` from `organization`, plus `categories` = MIS columns as `build_category_master` rows. Cache in-process for 60 s. | `reports/db.py` | T2.1 | 0.6 | todo |
| T2.3 | `monthly_trial_balance.account_rows`: use `snapshot["categories"]` when present, else `cm.build_category_master(...)` (CLI path unchanged). | `reports/monthly_trial_balance.py` | T2.2 | 0.2 | todo |
| T2.4 | `server._cached_snapshot()` → `db.coa_snapshot()`; `/api/config` FY month from it; `_org_currency` from `organization`. | `server.py` | T2.2 | 0.2 | todo |
| T2.5 | `get_category_master()` → `SELECT … FROM accounts` with `account_name AS ledger_name` and `path` rebuilt from `parent_account_id`; `save_category_master()` → `UPDATE accounts SET group_ledger, pl_bs, category, sub_category, source, note WHERE account_id=…` (no inserts, no deletes; the seeder owns rows). | `reports/db.py` | T0.3 | 0.5 | todo |
| T2.6 | Editor endpoints: `GET /api/category-master` from `accounts`; override save / delete = write CSV (as today) → `build_category_master(db.coa_snapshot(), overrides)` → `save_category_master()`. Remove `POST /api/refresh` and its button. | `server.py`, `web/assets/category-master.js` | T2.2, T2.5 | 0.5 | todo |
| T2.7 | CLI `category-master`: build from `db.coa_snapshot()` + overrides and `save_category_master()`; keep file outputs. | `main.py` | T2.5 | 0.2 | todo |

### P3 — UI and Excel (~1.5 h)

| ID | Task | Files | Depends | h | Status |
|---|---|---|---|---|---|
| T3.1 | Remove `pickRun()`, the run selector, `api/runs`, `run_id` URLs and the stored-run branches for financial tabs; Excel button always `api/export.xlsx?cols=…`. | `web/assets/reports.js`, `web/reports.html` | P1, P2 | 0.6 | todo |
| T3.2 | Margin dims: add `["location","Location"]`; label `van` "Van". Line detail columns: `purchase_price`, `flag`; drop `cost_rate`, `cost_source`. COGS labels per *Defaults*. Empty state: "No sales loaded for … (load via seeder)". | `web/assets/reports.js` | T1.2, T1.3 | 0.4 | todo |
| T3.3 | `excel_export`: delete `build_workbook` and the run helpers (`_period`, `_statement_sheets`, `_trial_balance_sheet`, `_matching_run`, `_pivot_sheets`); `build_live_workbook` adds the Location dim; Category Master sheet from `get_category_master()`. | `reports/excel_export.py` | T1.2, T2.5 | 0.4 | todo |

### P4 — Remove the run code (~1 h)

| ID | Task | Files | Depends | h | Status |
|---|---|---|---|---|---|
| T4.1 | `server.py`: delete `/api/runs`, `/api/run`, every `run_id` branch of `/api/statement`, `/api/tb`, `/api/margin`, `/api/margin-detail`, `/api/purchases`, `/api/export.xlsx`; update the module docstring. | `server.py` | T3.1, T3.3 | 0.3 | todo |
| T4.2 | `main.py`: delete `margin`, `purchases`, `db-load`, `db-runs`, `db-migrate-runs`; `financials` stops calling `save_financials_run`; `_db_save` message removed. | `main.py` | T4.1 | 0.3 | todo |
| T4.3 | `db.py`: delete run / dual-write functions (`_new_run`, `save_*_run` except cashflow, `_replace_*`, `sync_sales`, `sync_purchases`, `migrate_runs_to_dated`, `_backfill_invoice_headers`, `_migrate_margin`, `list_runs`, `get_run`, `delete_run`, `get_statement*`, `get_trial_balance`, run-based `get_*_pivot` / `get_margin_detail`, `MARGIN_DB_COLUMNS`, `MARGIN_INVOICE_DB_COLUMNS`, `PURCHASE_DB_COLUMNS`). Keep `_set_coverage` only if something still calls it. | `reports/db.py` | T4.2 | 0.3 | todo |
| T4.4 | Delete modules / scripts with no remaining import: check `invoice_margin.py`, `purchases.py`, `build_inv_tables.py` (`grep -r` first; `live_financials` and the sales dashboard must not import them). | `reports/`, repo root | T4.3 | 0.1 | todo |

### P5 — Tests and docs (~1 h)

| ID | Task | Files | Depends | h | Status |
|---|---|---|---|---|---|
| T5.1 | Delete `tests/test_sync_replace.py`. Remove any DB-backed cases from `test_date_columns.py`. | `tests/` | T4.3 | 0.1 | todo |
| T5.2 | Unit tests without a DB: the margin / purchase SQL fragments contain the status filter and the dimension expressions; `coa_snapshot` mapping from a fake `accounts` row list (pure helper); `account_rows` uses `snapshot["categories"]` when given. | `tests/test_report_sql.py` (new) | P1, P2 | 0.5 | todo |
| T5.3 | `tests/test_live_financials.py` still passes (snapshot shape unchanged). Run the whole `tests/` suite. | — | T5.2 | 0.1 | todo |
| T5.4 | `README.md` / `ZOHO_API_CONTEXT.md`: new DB, removed commands, seeder contract pointer. Mark old tasks file as superseded. | docs | P4 | 0.3 | todo |

### P6 — Verify on dev (needs seeded data)

| ID | Task | Depends | Status |
|---|---|---|---|
| T6.1 | With the seeder's first load: Margin (all 5 dims, detail both views), Purchases, coverage hint, live TB / P&L / BS / Executive Summary, category edit + delete, Excel export — all on dev in a browser. | P0–P5, seeded data | todo |
| T6.2 | Spot check: Margin `net_sales` for one month = `SUM(net_sales)` of non-draft/void `sales_invoices` for that month. | T6.1 | todo |

### Later / parked

| ID | Task | Status |
|---|---|---|
| T9.1 | Credit and debit notes in Margin: signed UNION (`v_sales_net_lines`, `doc_type`), notes as rows in invoice detail (D6). | parked |
| T9.2 | `gl_journals` loader, seed from `cost_of_sales_nellon` / `inventory_postings`, check vs live TB (D2). Needs Zoho-call approval. | parked |
| T9.3 | Prod and test-site cut-over to `zoho-koyson` (D13): seed prod DB, deploy, switch `MIS_DB_NAME`, keep `nellon_mis` as backup. Needs approval. | parked |
| T9.4 | Cashflow on `accounts` instead of `coa_snapshot.json`. | parked |

## Order and size

```
P0 (1 h) ──┬── P1 Margin/Purchases (2 h) ──┐
           └── P2 Accounts/financials (2.5 h) ┴── P3 UI + Excel (1.5 h) ── P4 Removal (1 h) ── P5 Tests/docs (1 h) ── P6 Verify (seeded data)
```

About 9 hours of work; P1 and P2 can run side by side. Nothing in P0–P5 calls Zoho.
P6 waits for the seeder.

## Seeder contract

What the reports assume about the tables. The seeder (out of scope) must meet these.

| Table | Must hold |
|---|---|
| `organization` | One row; `fiscal_year_start_month` = 1 (Zoho's 0), `currency_code`, `name`. |
| `accounts` | Every chart account with `parent_account_id`, `account_type`, `is_active`, and the MIS columns (`group_ledger`, `pl_bs`, `category`, `sub_category`, `source`, `note`) computed with `category_overrides.csv` taking priority. A reseed must keep `source='override'` rows' categories (apply the CSV). |
| `sales_invoices`, `sales_lines` | Debit notes excluded. `date` on every line = invoice date. `net_sales`, `cogs` in AED; header = sum of lines. Draft / void rows may be present (reports filter them). |
| `purchase_docs`, `purchase_lines` | `kind` ∈ `bill`, `purchase_order`; line `date` = document date; `amount` in AED; header = sum of lines. |
| `locations`, `vans` | Every `location_id` used on a line exists in `locations`; `vans` has a row per van location. |
| `sync_coverage` | After each load: `(dataset, from_date, to_date, synced_at, source)` with `dataset` = `sales` or `purchases`, merged / trimmed so ranges don't overlap. |

Foreign keys are on (`SET FOREIGN_KEY_CHECKS = 1` after load): masters first, then documents.
