"""Fetch Cost of Sales - Nellon (5.1.1000) postings from Zoho Books into MariaDB.

    GET /chartofaccounts/transactions?account_id=3331482000000034003&per_page=200&page=N
        [&date.start=YYYY-MM-DD&date.end=YYYY-MM-DD][&transaction_type=…]

One row per posting (Zoho's `categorized_transaction_id`) in table
`cost_of_sales_nellon`, so re-running over an overlapping range updates rows
instead of duplicating them. Shared logic: reports/account_postings.py.

Examples:

    # October 2026
    python fetch_cost_of_sales_nellon.py --from-date 2026-10-01 --to-date 2026-10-31

    # Invoice postings only
    python fetch_cost_of_sales_nellon.py --from-date 2026-10-01 --to-date 2026-10-31 \\
        --transaction-type inventory_valuation_for_invoice

    # Load a response saved earlier (no Zoho call)
    python fetch_cost_of_sales_nellon.py --from-json output/cos_raw_all.json

Invoice postings come back as `inventory_valuation_for_invoice`, not
`invoice` (filtering on `invoice` returns nothing). By default every type is
stored, so credit/debit-note reversals are kept and the table sums to the ledger.
"""

from __future__ import annotations

from reports.account_postings import run_cli

ACCOUNT_ID = "3331482000000034003"
ACCOUNT_CODE = "5.1.1000"
ACCOUNT_NAME = "Cost of Sales - Nellon"

TABLE = "cost_of_sales_nellon"


if __name__ == "__main__":
    raise SystemExit(run_cli(accounts={ACCOUNT_ID: ACCOUNT_CODE}, table=TABLE, description=__doc__))
