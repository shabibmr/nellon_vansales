"""Build `inv` and `inv_det`: one copy of every invoice, taken from the latest margin run holding it.

    margin_invoices -> inv       (PK invoice_id)
    margin_lines    -> inv_det   (PK invoice_id, line_no)

Both keep the source `run_id` column for provenance. An invoice that appears in several runs
(e.g. September in runs 6 and 7) is taken whole - header and all its lines - from the highest
run_id. margin_invoices / margin_lines are only read, never changed. Re-running rebuilds
`inv` and `inv_det` from scratch in one transaction.

    python build_inv_tables.py             # rebuild
    python build_inv_tables.py --dry-run   # show what would be copied, write nothing
"""
from __future__ import annotations

import argparse

from reports import db

LATEST = """(SELECT invoice_id, MAX(run_id) AS run_id FROM margin_invoices GROUP BY invoice_id)"""


def _ensure(cur, table: str, like: str, pk: str) -> None:
    cur.execute("SHOW TABLES LIKE %s", (table,))
    if cur.fetchone():
        return
    cur.execute(f"CREATE TABLE {table} LIKE {like}")
    cur.execute(f"ALTER TABLE {table} DROP PRIMARY KEY, ADD PRIMARY KEY ({pk})")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="count only, create/write nothing")
    args = ap.parse_args()

    with db.connect() as conn:
        cur = conn.cursor()

        cur.execute(f"""SELECT COUNT(*) AS n, COUNT(DISTINCT m.invoice_id) AS u FROM margin_invoices m""")
        src = cur.fetchone()
        cur.execute(f"""SELECT l.run_id, COUNT(*) AS n FROM margin_invoices m
                        JOIN {LATEST} l ON l.invoice_id = m.invoice_id AND l.run_id = m.run_id
                        GROUP BY l.run_id ORDER BY l.run_id""")
        picked = cur.fetchall()
        print(f"margin_invoices: {src['n']} rows, {src['u']} distinct invoices")
        for r in picked:
            print(f"  from run {r['run_id']}: {r['n']} invoices")
        if args.dry_run:
            return

        _ensure(cur, "inv", "margin_invoices", "invoice_id")
        _ensure(cur, "inv_det", "margin_lines", "invoice_id, line_no")

        cur.execute("DELETE FROM inv_det")
        cur.execute("DELETE FROM inv")
        cur.execute(f"""INSERT INTO inv
                        SELECT m.* FROM margin_invoices m
                        JOIN {LATEST} l ON l.invoice_id = m.invoice_id AND l.run_id = m.run_id""")
        cur.execute(f"""INSERT INTO inv_det
                        SELECT d.* FROM margin_lines d
                        JOIN {LATEST} l ON l.invoice_id = d.invoice_id AND l.run_id = d.run_id""")

        cur.execute("SELECT COUNT(*) AS n FROM inv")
        n_inv = cur.fetchone()["n"]
        cur.execute("SELECT COUNT(*) AS n FROM inv_det")
        n_det = cur.fetchone()["n"]
        print(f"inv: {n_inv} rows   inv_det: {n_det} rows")


if __name__ == "__main__":
    main()
