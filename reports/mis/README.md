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

## Planned next

- Profit & Loss (`/reports/profitandloss`)
- Balance Sheet (`/reports/balancesheet`)
- Cash Flow (`/reports/cashflow`)
- Consolidated workbook
- Item-wise invoice COGS (`purchase_price × qty` on invoice line items)
