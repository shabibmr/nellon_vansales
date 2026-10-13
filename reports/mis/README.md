# Nellon MIS reports (Zoho Books)

Python CLI that builds management reports from Zoho Books APIs.

Credentials: `../../.env_zoho` (`ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN`, `ZOHO_ORG_ID`).

## Setup

```bash
cd reports/mis
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Trial balance

Built from **General Ledger + Chart of Accounts**, not from `/journals`.

Manual journals alone omit invoices, bills, expenses, and receipts. The period
ledger covers all postings:

- `GET /reports/generalledger?filter_by=TransactionDate.CustomDate&from_date=&to_date=`
- `GET /chartofaccounts?showbalance=true` (account type / parent / active)

```bash
.venv/bin/python main.py trial-balance --from-date 2026-04-01 --to-date 2026-10-11
```

Outputs under `output/`:

- CSV — one row per account
- Excel — `TrialBalance` + `Summary` sheets
- JSON — summary + rows

Columns: account code/name/type, gross `debit_total` / `credit_total`, net debit/credit, balance.

## Monthly trial balance

One row per account: opening, a net movement column per calendar month, period
gross Dr/Cr, closing, plus Category Master columns (PL/BS, Category, Sub Category).
All amounts are signed **debit positive** (Dr +, Cr −).

```bash
.venv/bin/python main.py monthly-tb --from-date 2026-04-01 --to-date 2026-09-30
.venv/bin/python main.py monthly-tb --from-date 2026-04-01 --fy-start-month 4 --cached-coa
```

- GL report returns period movement only, so opening = GL from 2000-01-01 to the day before `--from-date`.
- P&L accounts reset each financial year (start month from the Zoho organization, or `--fy-start-month`);
  earlier years' P&L is carried as one row, `Prior years P&L (retained)` → Reserves and surplus.
- Exit code 1 if opening or closing don't net to zero.

Outputs `output/monthly_tb_<from>_<to>_<stamp>.{csv,xlsx,json}`.

## Financial statements (Executive Summary, P&L, Balance Sheet)

Built from the monthly trial balance + Category Master, laid out like
`report-template.xlsx`. Pure Python (`reports/financials.py`) — can be rebuilt
offline from a saved TB JSON.

```bash
.venv/bin/python main.py financials --tb-json output/monthly_tb_<from>_<to>_<stamp>.json   # no Zoho calls
.venv/bin/python main.py financials --from-date 2026-04-01 --to-date 2026-09-30          # pulls TB first
```

Workbook `output/mis_<from>_<to>_<stamp>.xlsx` sheets: Executive Summary, PL, BS,
MonthlyTB, Category Master.

- P&L / Exec Summary: one column per month + Total. Revenue → COGS → GM → Direct
  Expenses → CM → Other Income → Fixed Expenses → EBITDA → Finance Cost →
  Depreciation → FX → PBT → Income Tax → Net Profit, with GM/CM/EBITDA/NP %.
- BS: one column per month end; Current Year Earnings = FY-to-date P&L.
- Each statement ends with a check row (P&L vs TB, Assets vs Capital & Liabilities);
  exit code 1 if any check is off. Categories a statement doesn't know land in an
  "Unmapped …" line instead of disappearing.

## Invoice margin

Revenue and margin per invoice line, plus By Month / Item / Customer /
Salesperson / Van sheets.

```bash
.venv/bin/python main.py margin --from-date 2026-09-01 --to-date 2026-09-30
.venv/bin/python main.py margin --from-date 2026-09-01 --to-date 2026-09-30 --offline   # cache only
```

- Net sales = line total net of tax, less line discount and an allocated share of any
  whole-invoice discount, in base currency. Void/draft invoices skipped.
- Cost = item's **current** `purchase_rate` × base quantity (alternate units converted via
  the item's `unit_conversions`). Standard-cost view — may differ from ledger COGS in the P&L.
- Invoice details are cached in `output/cache/` and re-fetched only when an invoice's
  `last_modified_time` changes; calls are throttled to stay under Zoho's ~100/min limit.
  The first run for a month costs ~1 call per invoice.
- `flag` column marks lines with no item, no purchase rate, or an unknown unit conversion.
- Credit notes / returns are not netted yet.

## Category Master

Maps every Zoho ledger to the MIS reporting lines (PL/BS → Category → Sub Category)
used by the P&L, Balance Sheet and Executive Summary in `report-template.xlsx`.
Built from `GET /chartofaccounts`; rules live in `reports/category_master.py`.

```bash
.venv/bin/python main.py category-master          # pull COA from Zoho, write output/category_master.{csv,xlsx,json}
.venv/bin/python main.py category-master --cached # reuse output/coa_snapshot.json
.venv/bin/python main.py serve                    # read-only view at http://127.0.0.1:8765/categories
```

Each account is resolved in this order (the `source` column says which step decided):

1. `override` — `category_overrides.csv` (keyed by `account_id`; committed, edited by hand, then re-run `category-master`)
2. `rule` / `review` — name pattern, then the nearest ancestor in the Zoho account tree with a rule.
   `review` rows have a suggested category but are judgement calls to confirm
   (investor profit shares, partner/related-party accounts, Zoho suspense accounts).
3. `type` — fallback on Zoho `account_type`

New Zoho accounts are picked up automatically on the next run; overrides survive re-runs.
The web page is read-only (no override editing over HTTP); it is deployed publicly at
https://algoray.tech/koyson-zoho/acc-reports/categories via the `koyson-mis-web` service.

## MariaDB storage + report viewer

Processed data is stored in MariaDB (database `nellon_mis`; settings in the
git-ignored `.env`: `MIS_DB_HOST/PORT/USER/PASSWORD/NAME`). Schema lives in
`reports/db.py`.

```bash
.venv/bin/pip install -r requirements.txt       # adds pymysql
.venv/bin/python main.py db-init                 # create DB + tables (idempotent)
.venv/bin/python main.py financials --from-date 2026-04-01 --to-date 2026-09-30   # also saves a run
.venv/bin/python main.py margin --from-date 2026-09-01 --to-date 2026-09-30       # also saves a run
.venv/bin/python main.py db-load --tb-json output/monthly_tb_<…>.json             # import saved JSON, no Zoho
.venv/bin/python main.py db-runs                 # list runs;  --delete <id> removes one
.venv/bin/python main.py serve                   # http://127.0.0.1:8765/reports
```

Tables: `report_runs` (one per financials/margin run) → `tb_accounts`, `tb_monthly`,
`statement_lines`, `statement_values`, `margin_lines` (all cascade-delete with the run),
plus `category_master` (current mapping, upserted by `category-master`).
Pass `--no-db` to `financials` / `margin` / `purchases` / `category-master` to skip saving.

Web UI (served by `main.py serve`): `web/reports.html` (`/reports`) and `web/category_master.html` (`/`), sharing `web/assets/app.css` (Material 3-inspired tokens, nav rail, components) and the Material Symbols sprite `web/assets/icons.svg`; page logic in `web/assets/reports.js` / `category-master.js`. The report viewer reads only MariaDB, never Zoho. Tabs: Executive Summary,
Profit & Loss, Balance Sheet, Trial Balance (by category, opening → months → closing),
Margin (rows by item / customer / salesperson / van × months; net sales, margin, GM %,
cost or quantity), Purchases (bills + purchase orders; rows by vendor / item / kind × months;
amount, quantity or document count). Run `main.py db-init` once to create the `purchase_lines` table. Month columns are labelled like the template (`Apr-26 … Total`).
**Export Excel** (financials tabs) downloads one workbook built from MariaDB with a sheet
per report: Executive Summary, PL, BS, Trial Balance (`/api/export.xlsx?run_id=`).

## Zoho Books web tab

```bash
.venv/bin/python main.py webtab     # adds "MIS Reports" -> https://algoray.tech/koyson-zoho/acc-reports/
```

Uses `POST /settings/tabs` (scope `ZohoBooks.settings.CREATE`), shared with all users. Idempotent: lists
tabs first and skips if one with the same name exists (1-2 calls). Note the live API returns
`tabs` / `tab_id`, not `web_tabs` / `webtab_id` as the published docs say. The web tab shows
Executive Summary, P&L, BS, Trial Balance, Margin and Purchases.

## Ledger postings (Cost of Sales - Nellon ↔ Inventory)

```bash
.venv/bin/python fetch_cost_of_sales_nellon.py --from-date 2026-10-01 --to-date 2026-10-31
.venv/bin/python fetch_inventory.py           --from-date 2026-10-01 --to-date 2026-10-31
```

Both page through `GET /chartofaccounts/transactions` (200 per page) and upsert one row per posting
(key `account_id, categorized_transaction_id`); shared code in `reports/account_postings.py`.

- `cost_of_sales_nellon`: 5.1.1000. Invoice postings are type `inventory_valuation_for_invoice`
  (filtering on `invoice` returns nothing).
- `inventory_postings`: Inventory 1.5.1000 + Other Inventory 1.5.9000, every type (bills,
  valuations, credit notes, adjustments). Always pass a date range.
- View `cos_inventory_match` pairs the two by `transaction_id`: `cos_amount + inventory_amount =
  difference` (should be 0); `status` is matched / cos_only / inventory_only.

`--from-json` (repeatable) loads saved responses with no Zoho call; each script refuses postings for
any account other than its own.

## Planned next

- Cash Flow
- Net credit notes / sales returns into the margin report
