"""Seed gl_journals (zoho-koyson schema) from cost_of_sales_nellon / inventory_postings.

Source (read-only): nellon_mis_dev.cost_of_sales_nellon and .inventory_postings, which
already have the gl_journals column shape. Target: gl_journals in the zoho-koyson schema.

Usage:
    python seed_gl_journals.py                 # dry-run: validate and report, no writes
    python seed_gl_journals.py --apply         # upsert into the target database

Upserts by (account_id, categorized_transaction_id). It never deletes: stale rows from a
voided posting are only removed by a later full ledger fetch (see DB-Schema-Proposed.md).
Only the accounts held in these two tables get rows. The trial balance will not sum to
zero until every ledger account has been fetched from Zoho.
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

import pymysql
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / ".env.mis")

SOURCES = ("cost_of_sales_nellon", "inventory_postings")
COLUMNS = [
    "account_id", "categorized_transaction_id", "account_name", "account_code",
    "transaction_id", "transaction_type", "transaction_type_formatted", "transaction_date",
    "entry_number", "reference_number", "customer_id", "payee", "description",
    "debit_or_credit", "debit_amount", "credit_amount", "amount", "fcy_debit_amount",
    "fcy_credit_amount", "currency_id", "currency_code", "offset_account_name",
    "raw_json", "fetched_at",
]
SQL = (
    "INSERT INTO gl_journals ({cols}) VALUES ({vals}) ON DUPLICATE KEY UPDATE {upd}".format(
        cols=", ".join(f"`{c}`" for c in COLUMNS),
        vals=", ".join(f"%({c})s" for c in COLUMNS),
        upd=", ".join(
            f"`{c}` = VALUES(`{c}`)" for c in COLUMNS[2:]
        ),
    )
)


def connect(db: str) -> pymysql.Connection:
    return pymysql.connect(
        host=os.getenv("MIS_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("MIS_DB_PORT", "3306")),
        user=os.getenv("MIS_DB_USER", "user2grey"),
        password=os.getenv("MIS_DB_PASSWORD", "user2grey"),
        database=db,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def table_exists(cur, name: str) -> bool:
    cur.execute("SHOW TABLES LIKE %s", (name,))
    return cur.fetchone() is not None


def load_rows(src: pymysql.Connection) -> tuple[list[dict], Counter]:
    rows: list[dict] = []
    per_source: Counter = Counter()
    with src.cursor() as cur:
        for t in SOURCES:
            if not table_exists(cur, t):
                print(f"  {t}: not in source, skipped")
                continue
            cur.execute(f"SELECT {', '.join(f'`{c}`' for c in COLUMNS)} FROM `{t}`")
            got = cur.fetchall()
            per_source[t] = len(got)
            rows.extend(got)
    return rows, per_source


def validate(rows: list[dict]) -> Counter:
    p: Counter = Counter()
    seen: set[tuple] = set()
    for r in rows:
        key = (r["account_id"], r["categorized_transaction_id"])
        if not r["account_id"] or not r["categorized_transaction_id"]:
            p["blank_key"] += 1
        if key in seen:
            p["duplicate_key_across_sources"] += 1
        seen.add(key)
        if r["transaction_date"] is None:
            p["null_transaction_date"] += 1
        if abs(Decimal(r["amount"]) - (Decimal(r["debit_amount"]) - Decimal(r["credit_amount"]))) > Decimal("0.005"):
            p["amount_ne_debit_minus_credit"] += 1
    return p


def report(rows: list[dict], per_source: Counter, problems: Counter) -> None:
    print(f"Rows read: {len(rows):,}  " + ", ".join(f"{k}={v:,}" for k, v in per_source.items()))
    by_type: dict[str, list] = defaultdict(lambda: [0, Decimal("0")])
    by_acct: dict[str, list] = defaultdict(lambda: [0, Decimal("0")])
    for r in rows:
        by_type[r["transaction_type"]][0] += 1
        by_type[r["transaction_type"]][1] += Decimal(r["amount"])
        by_acct[f'{r["account_id"]} {r["account_name"]}'][0] += 1
        by_acct[f'{r["account_id"]} {r["account_name"]}'][1] += Decimal(r["amount"])
    dates = [r["transaction_date"] for r in rows if r["transaction_date"]]
    if dates:
        print(f"Dates: {min(dates)} .. {max(dates)}")
    print("By account:")
    for k, (n, s) in sorted(by_acct.items()):
        print(f"  {k}: {n:,} rows, net {s:,.2f}")
    print("By transaction_type:")
    for k, (n, s) in sorted(by_type.items()):
        print(f"  {k or '(blank)'}: {n:,} rows, net {s:,.2f}")
    print(f"Validation problems: {dict(problems) or 'none'}")


def target_report(tgt: pymysql.Connection, rows: list[dict]) -> bool:
    ok = True
    print("\n--- Target checks (read-only) ---")
    with tgt.cursor() as cur:
        for t in ("accounts", "gl_journals"):
            if not table_exists(cur, t):
                print(f"  {t}: MISSING in target (create the schema first)")
                return False
        cur.execute("SELECT COUNT(*) AS n FROM gl_journals")
        print(f"  gl_journals: {cur.fetchone()['n']:,} existing rows")
        cur.execute("SELECT account_id FROM accounts")
        have = {x["account_id"] for x in cur.fetchall()}
        need = {r["account_id"] for r in rows}
        missing = need - have
        print(f"  accounts: {len(need - missing)} of {len(need)} referenced account(s) present")
        if missing:
            ok = False
            print(f"  MISSING accounts (FK would fail): {sorted(missing)}")
        if table_exists(cur, "sales_invoices"):
            cur.execute(
                """SELECT COUNT(*) AS n, SUM(ABS(s.cogs - IFNULL(g.s, 0)) <= 0.01) AS tied,
                          SUM(g.s IS NULL) AS no_ledger_row
                   FROM sales_invoices s
                   LEFT JOIN (SELECT transaction_id, SUM(amount) AS s FROM (
                                SELECT transaction_id, amount FROM gl_journals
                                 WHERE transaction_type = 'inventory_valuation_for_invoice') x
                              GROUP BY transaction_id) g ON g.transaction_id = s.invoice_id"""
            )
            print(f"  sales_invoices vs gl_journals NOW (before this load): {cur.fetchone()}")
        # same tie-out, simulated from the rows about to be loaded
        by_inv: dict[str, Decimal] = defaultdict(Decimal)
        for r in rows:
            if r["transaction_type"] == "inventory_valuation_for_invoice":
                by_inv[r["transaction_id"]] += Decimal(r["amount"])
        if table_exists(cur, "sales_invoices"):
            cur.execute("SELECT invoice_id, cogs FROM sales_invoices")
            inv = cur.fetchall()
            tied = sum(1 for i in inv if abs(Decimal(i["cogs"]) - by_inv.get(i["invoice_id"], Decimal(0))) <= Decimal("0.01"))
            missing_inv = sum(1 for i in inv if i["invoice_id"] not in by_inv)
            print(f"  After load: {tied:,} of {len(inv):,} invoices tie to the ledger; "
                  f"{missing_inv} invoice(s) have no ledger row")
    return ok


def apply(tgt: pymysql.Connection, rows: list[dict]) -> None:
    with tgt.cursor() as cur:
        for i in range(0, len(rows), 1000):
            cur.executemany(SQL, rows[i : i + 1000])
    tgt.commit()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", default="nellon_mis_dev")
    ap.add_argument("--target", default="zoho-koyson")
    ap.add_argument("--apply", action="store_true", help="write to the target (default: dry-run)")
    args = ap.parse_args()

    src = connect(args.source)
    try:
        rows, per_source = load_rows(src)
    finally:
        src.close()
    problems = validate(rows)

    print(f"Source: {args.source}   Target: {args.target}   Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
    report(rows, per_source, problems)

    tgt = connect(args.target)
    try:
        target_ok = target_report(tgt, rows)
        if not args.apply:
            print("\n[DRY RUN COMPLETE] Nothing was written. Re-run with --apply to upsert.")
            return 0
        if problems or not target_ok:
            print("Refusing to apply: fix the problems above first.", file=sys.stderr)
            return 1
        apply(tgt, rows)
        print(f"\nCommitted {len(rows):,} rows.")
    except Exception:
        tgt.rollback()
        raise
    finally:
        tgt.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
