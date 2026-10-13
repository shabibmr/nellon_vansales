"""Fetch Inventory (1.5.1000) and Other Inventory (1.5.9000) postings into MariaDB.

    GET /chartofaccounts/transactions?account_id=…&per_page=200&page=N
        &date.start=YYYY-MM-DD&date.end=YYYY-MM-DD[&transaction_type=…]

The Cr side of the invoice cost journals stored by fetch_cost_of_sales_nellon.py
(Zoho leaves `offset_account_name` empty, so it has to come from the inventory
accounts). Both accounts go into table `inventory_postings`, one row per
posting; `account_id` / `account_code` tell them apart. Every transaction type
is kept: bills (stock in), invoice valuations (stock out), credit notes,
vendor credits, adjustments.

View `cos_inventory_match` pairs the two sides by `transaction_id`:
`cos_amount` (Dr +) + `inventory_amount` (Cr -) = `difference`, which should
be 0. `status` is matched / cos_only / inventory_only; inventory_only rows are
valuations whose cost went to another COGS account.

The inventory accounts carry far more postings than COS, so always give a
date range on a live run:

    python fetch_inventory.py --from-date 2026-10-01 --to-date 2026-10-31

    # Load saved responses, one per account (no Zoho call)
    python fetch_inventory.py --from-json output/inv_1.json --from-json output/inv_2.json
"""

from __future__ import annotations

from fetch_cost_of_sales_nellon import TABLE as COS_TABLE
from reports import db
from reports.account_postings import ddl, run_cli

ACCOUNTS = {
    "3331482000000034001": "1.5.1000",  # Inventory
    "3331482000000119043": "1.5.9000",  # Other Inventory
}

TABLE = "inventory_postings"
VIEW = "cos_inventory_match"

# MariaDB has no FULL JOIN: COS left-join inventory, UNION inventory rows with no COS side.
# Only valuation postings count on the inventory side; bills and adjustments have no COS leg.
VIEW_SQL = f"""
CREATE OR REPLACE VIEW {VIEW} AS
SELECT c.transaction_id, c.entry_number, c.transaction_date, c.payee, c.transaction_type,
       c.amount AS cos_amount, COALESCE(i.amount, 0) AS inventory_amount,
       c.amount + COALESCE(i.amount, 0) AS difference,
       IF(i.transaction_id IS NULL, 'cos_only', 'matched') AS status
FROM (SELECT transaction_id, MIN(entry_number) AS entry_number, MIN(transaction_date) AS transaction_date,
             MIN(payee) AS payee, MIN(transaction_type) AS transaction_type, SUM(amount) AS amount
      FROM {COS_TABLE} GROUP BY transaction_id) c
LEFT JOIN (SELECT transaction_id, SUM(amount) AS amount
           FROM {TABLE} WHERE transaction_type LIKE 'inventory\\_valuation\\_for\\_%'
           GROUP BY transaction_id) i ON i.transaction_id = c.transaction_id
UNION ALL
SELECT i.transaction_id, i.entry_number, i.transaction_date, i.payee, i.transaction_type,
       0, i.amount, i.amount, 'inventory_only'
FROM (SELECT transaction_id, MIN(entry_number) AS entry_number, MIN(transaction_date) AS transaction_date,
             MIN(payee) AS payee, MIN(transaction_type) AS transaction_type, SUM(amount) AS amount
      FROM {TABLE} WHERE transaction_type LIKE 'inventory\\_valuation\\_for\\_%'
      GROUP BY transaction_id) i
LEFT JOIN (SELECT DISTINCT transaction_id FROM {COS_TABLE}) c ON c.transaction_id = i.transaction_id
WHERE c.transaction_id IS NULL
"""


def create_view() -> None:
    with db.connect() as conn, conn.cursor() as cur:
        cur.execute(ddl(COS_TABLE))  # the view needs both tables, even before a COS run
        cur.execute(VIEW_SQL)
    print(f"View {VIEW} refreshed")


if __name__ == "__main__":
    raise SystemExit(run_cli(accounts=ACCOUNTS, table=TABLE, description=__doc__, after_save=create_view))
