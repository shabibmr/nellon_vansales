"""Replace cost_of_sales_nellon postings for a date range with a saved Zoho response (no Zoho call).

    GET /chartofaccounts/transactions?account_id=…&date_start=…&date_end=…   (note: date_start, not date.start)

Rows dated inside the range that Zoho no longer lists (postings it has since replaced under a new
categorized_transaction_id) are deleted, after being written to --backup; Zoho's rows are upserted.
One transaction, so a failure leaves the table unchanged.

    python refresh_cos_nellon_range.py --json cos_sep01_oct17.json --from-date 2026-09-01 --to-date 2026-10-17 \\
        --backup cos_stale_rows_backup.json [--dry-run]
"""
from __future__ import annotations

import argparse
import datetime
import decimal
import json

from reports import db
from reports.account_postings import to_row

TABLE = "cost_of_sales_nellon"
PAGE_CONTEXT = {"account_name": "Cost of Sales - Nellon", "account_code": "5.1.1000"}


def _json_default(o):
    if isinstance(o, (datetime.date, datetime.datetime, decimal.Decimal)):
        return str(o)
    raise TypeError(type(o))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", required=True, help="saved list of Zoho transactions")
    ap.add_argument("--from-date", required=True)
    ap.add_argument("--to-date", required=True)
    ap.add_argument("--backup", required=True, help="where to write the rows being deleted")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rows = [to_row(t, PAGE_CONTEXT) for t in json.load(open(args.json))]
    dates = [r["transaction_date"] for r in rows]
    if not rows or min(dates) < args.from_date or max(dates) > args.to_date:
        raise SystemExit("saved response is empty or outside the given range; nothing changed")
    keep = {r["categorized_transaction_id"] for r in rows}
    cols = list(rows[0])
    upd = ", ".join(f"{c}=VALUES({c})" for c in cols if c not in ("account_id", "categorized_transaction_id"))

    with db.connect() as conn:
        cur = conn.cursor()
        cur.execute(f"SELECT * FROM {TABLE} WHERE transaction_date BETWEEN %s AND %s", (args.from_date, args.to_date))
        stale = [r for r in cur.fetchall() if r["categorized_transaction_id"] not in keep]
        print(f"zoho rows {len(rows)}; stale rows to delete {len(stale)}")
        if args.dry_run:
            return
        json.dump(stale, open(args.backup, "w"), default=_json_default)
        for r in stale:
            cur.execute(f"DELETE FROM {TABLE} WHERE account_id=%s AND categorized_transaction_id=%s",
                        (r["account_id"], r["categorized_transaction_id"]))
        cur.executemany(
            f"INSERT INTO {TABLE} ({', '.join(cols)}) VALUES ({', '.join(['%s'] * len(cols))}) "
            f"ON DUPLICATE KEY UPDATE {upd}",
            [tuple(r[k] for k in cols) for r in rows],
        )
        print(f"deleted {len(stale)}, upserted {len(rows)}")


if __name__ == "__main__":
    main()
