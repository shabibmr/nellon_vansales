# Nellon MIS reports (Zoho Books)

Python CLI that builds management reports from Zoho Books APIs.

Credentials: `../../.env_zoho` (`ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN`, `ZOHO_ORG_ID`).

## Setup

```bash
cd reports/mis
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Layout

| Folder | What lives there |
|--------|------------------|
| `web/` | Frontend only: the four pages and `web/assets/`. Served by `backend/server.py`. |
| `backend/` | The CLI and report server (`python -m backend <command>`): `main.py`, `server.py`, `exporters.py`, and `backend/reports/` (financials, trial balance, cashflow, category master, live financials, web-tab JWT auth). |
| `zoho_sync/` | The Zoho → MariaDB sync (`python -m zoho_sync run`). |
| `common/` | Code both the backend and the sync import: `zoho_client.py`, `seed_common.py`, `db.py` (schema + queries), `periods.py`, `account_postings.py`. |
| `scripts/` | One-off fetch, seed, reconcile and test-invoice scripts. Run from `reports/mis` as `python -m scripts.<name>`. |
| `deploy/` | systemd units, PHP shims and deploy scripts. |

`common/` must not import from `backend/` or `zoho_sync/`. One exception today: `common/db.py` lazily imports `_fy_start_month` from `backend/reports/category_master.py`.

## Trial balance

Built from **General Ledger + Chart of Accounts**, not from `/journals`.

Manual journals alone omit invoices, bills, expenses, and receipts. The period
ledger covers all postings:

- `GET /reports/generalledger?filter_by=TransactionDate.CustomDate&from_date=&to_date=`
- `GET /chartofaccounts?showbalance=true` (account type / parent / active)

```bash
.venv/bin/python -m backend trial-balance --from-date 2026-04-01 --to-date 2026-10-11
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
.venv/bin/python -m backend monthly-tb --from-date 2026-04-01 --to-date 2026-09-30
.venv/bin/python -m backend monthly-tb --from-date 2026-04-01 --fy-start-month 4 --cached-coa
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
.venv/bin/python -m backend financials --tb-json output/monthly_tb_<from>_<to>_<stamp>.json   # no Zoho calls
.venv/bin/python -m backend financials --from-date 2026-04-01 --to-date 2026-09-30          # pulls TB first
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
- Web viewer: P&L and Executive Summary are expandable trees (section → category →
  sub-category → account), rebuilt from the run's stored TB so every parent equals the
  sum of its children. Outline level 1–4, Largest-first order, and Find (auto-expands
  to matches). The Excel export keeps the flat layout.

## Invoice margin

Margin and Purchases read the seeded tables `sales_invoices` / `sales_lines` and
`purchase_docs` / `purchase_lines` in `zoho-koyson`. The MIS no longer fetches them from
Zoho; the seeder loads them (contract: `proposal/Sync_Logic.md`).

- Net sales = line net sales; **COGS** = the booked per-line cost (`sales_lines.cogs`, from the
  invoice line's `purchase_price`). Void/draft invoices are skipped.
- Dimensions: item, customer, salesperson, van, location. `flag` marks lines the seeder
  could not cost.
- Credit notes / returns are not netted yet.

## Category Master

Maps every Zoho ledger to the MIS reporting lines (PL/BS → Category → Sub Category)
used by the P&L, Balance Sheet and Executive Summary in `report-template.xlsx`.
Built from the `accounts` table (the seeder loads the chart); rules live in `reports/category_master.py`.

```bash
.venv/bin/python -m backend category-master          # build from the `accounts` table, write output/category_master.{csv,xlsx,json}
.venv/bin/python -m backend serve                    # read-only view at http://127.0.0.1:8765/categories
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

Data lives in MariaDB database `zoho-koyson` (settings in the git-ignored `.env`:
`MIS_DB_HOST/PORT/USER/PASSWORD/NAME`). Schema: `reports/db.py` (`SCHEMA`), described in
`proposal/DB-Schema-Proposed.md`. A separate seeder loads it; the MIS only reads, except
`org-sync` and category overrides (`accounts.source='override'`).

```bash
.venv/bin/python -m backend db-init       # create DB + tables (idempotent)
.venv/bin/python -m backend db-coverage   # date ranges loaded, and gaps
.venv/bin/python -m backend serve         # http://127.0.0.1:8765/reports
```

The run-based commands (`margin`, `purchases`, `db-load`, `db-runs`, `db-migrate-runs`) and the
stored-run views (`?run=`, `run_id=`) are gone. `financials` still writes the Excel/JSON files
but no longer saves a run.

Web UI (served by `python -m backend serve`): `web/reports.html` (`/reports`) and `web/category_master.html` (`/`), sharing `web/assets/app.css` and `web/assets/icons.svg`; page logic in `web/assets/reports.js` / `category-master.js`. Tabs: Executive Summary,
Profit & Loss, Balance Sheet, Trial Balance (live from Zoho's General Ledger, cached),
Margin (rows by item / customer / salesperson / van / location × date columns; net sales, COGS, margin, GM %),
Purchases (bills + purchase orders; rows by vendor / item / kind × date columns).
**Export Excel** downloads one workbook for the selected columns (`/api/export.xlsx?cols=…`).

## Zoho Books web tab

```bash
.venv/bin/python -m backend webtab     # adds "MIS Reports" -> https://algoray.tech/koyson-zoho/acc-reports/
```

Uses `POST /settings/tabs` (scope `ZohoBooks.settings.CREATE`), shared with all users. Idempotent: lists
tabs first and skips if one with the same name exists (1-2 calls). Note the live API returns
`tabs` / `tab_id`, not `web_tabs` / `webtab_id` as the published docs say. The web tab shows
Executive Summary, P&L, BS, Trial Balance, Margin and Purchases.

## Ledger postings (Cost of Sales - Nellon ↔ Inventory)

```bash
.venv/bin/python -m scripts.fetch_cost_of_sales_nellon --from-date 2026-10-01 --to-date 2026-10-31
.venv/bin/python -m scripts.fetch_inventory           --from-date 2026-10-01 --to-date 2026-10-31
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
