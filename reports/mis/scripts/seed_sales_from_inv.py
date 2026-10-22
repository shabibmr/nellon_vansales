"""Seed sales_invoices / sales_lines (zoho-koyson schema) from inv / invoice_line_items.

Source (read-only): nellon_mis_dev.inv and nellon_mis_dev.invoice_line_items.
Target: sales_invoices and sales_lines as defined in proposal/DB-Schema-Proposed.sql.

Usage:
    python -m scripts.seed_sales_from_inv                 # dry-run: build rows, validate, report
    python -m scripts.seed_sales_from_inv --apply         # upsert into the target database

What is NOT seeded (no source in inv / invoice_line_items): salesperson_id, header
location, shipping_charge, adjustment, last_modified_time, and per line: location,
account, sku, tax_amount, line_discount, invoice_discount. Those need the Zoho cache
or API. Line net_sales is prorated from the header net_sales by item_total and the
line is flagged so a later recompute can find it.

cogs comes from the GL-reconciled cost_of_sales (reconcile_invoice_line_items.py).
Header cogs is exact. Per-line cogs on multi-line / single-line variance invoices is
an allocation, not Zoho's line valuation.
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter, defaultdict
from decimal import Decimal

import pymysql

from common.seed_common import connect, d, prorate, record_coverage, table_exists

PRORATE_FLAG = "net_sales prorated from header"


def build_rows(src: pymysql.Connection, item_ids: set[str]):
    with src.cursor() as cur:
        cur.execute(
            """SELECT invoice_id, invoice_number, date, due_date, status, customer_id,
                      customer_name, salesperson_name, currency_code, exchange_rate,
                      sub_total, discount_total, tax_total, total, balance,
                      net_sales, cost_of_sales, flagged_lines
               FROM inv ORDER BY date, invoice_number"""
        )
        invoices = cur.fetchall()
        cur.execute(
            """SELECT line_item_id, invoice_id, date, item_id, item_name, qty, uom,
                      base_uom, rate, item_total, purchase_price, conversion_rate,
                      base_qty, cost_of_sales
               FROM invoice_line_items ORDER BY invoice_id, line_item_id"""
        )
        lines = cur.fetchall()

    inv_ids = {r["invoice_id"] for r in invoices}
    by_inv: dict[str, list] = defaultdict(list)
    stats = Counter()
    for ln in lines:
        if ln["invoice_id"] not in inv_ids:
            stats["orphan_lines_skipped"] += 1
            continue
        by_inv[ln["invoice_id"]].append(ln)

    inv_rows, line_rows = [], []
    for r in invoices:
        inv_rows.append(
            {
                "invoice_id": r["invoice_id"],
                "invoice_number": r["invoice_number"] or "",
                "date": r["date"],
                "due_date": r["due_date"],
                "status": r["status"] or "",
                "customer_id": r["customer_id"] or None,
                "customer_name": r["customer_name"] or "",
                "salesperson_name": r["salesperson_name"] or "",
                "currency_code": r["currency_code"] or "AED",
                "exchange_rate": d(r["exchange_rate"], "1") or Decimal("1"),
                "sub_total": d(r["sub_total"]),
                "discount_total": d(r["discount_total"]),
                "tax_total": d(r["tax_total"]),
                "total": d(r["total"]),
                "balance": d(r["balance"]),
                "net_sales": d(r["net_sales"]),
                "cogs": d(r["cost_of_sales"]),
                "flagged_lines": int(r["flagged_lines"] or 0),
            }
        )
        group = by_inv.get(r["invoice_id"], [])
        shares = prorate(d(r["net_sales"]), [d(g["item_total"]) for g in group])
        for g, share in zip(group, shares):
            qty = d(g["qty"])
            conv = d(g["conversion_rate"], "1")
            flag = PRORATE_FLAG
            iid = g["item_id"] or None
            if iid is None:
                flag += "; missing item_id"
                stats["lines_missing_item_id"] += 1
            elif iid not in item_ids:
                flag += "; item_id not in items"
                stats["lines_item_not_in_items"] += 1
                iid = None
            line_rows.append(
                {
                    "line_item_id": g["line_item_id"],
                    "invoice_id": g["invoice_id"],
                    "date": g["date"] or r["date"],
                    "item_id": iid,
                    "item_name": g["item_name"] or "",
                    "quantity": qty,
                    "unit": g["uom"] or "",
                    "base_unit": g["base_uom"] or "",
                    "conversion_rate": conv,
                    "base_quantity": d(g["base_qty"], str(qty * conv)),
                    "rate": d(g["rate"]),
                    "item_total": d(g["item_total"]),
                    "net_sales": share,
                    "purchase_price": d(g["purchase_price"]),
                    "cogs": d(g["cost_of_sales"]),
                    "flag": flag[:255],
                }
            )
    return inv_rows, line_rows, stats


def validate(inv_rows, line_rows, stats) -> int:
    problems = 0
    line_sum_cogs: dict[str, Decimal] = defaultdict(Decimal)
    line_sum_ns: dict[str, Decimal] = defaultdict(Decimal)
    line_count: Counter = Counter()
    for ln in line_rows:
        line_sum_cogs[ln["invoice_id"]] += ln["cogs"]
        line_sum_ns[ln["invoice_id"]] += ln["net_sales"]
        line_count[ln["invoice_id"]] += 1
    no_lines = cogs_off = ns_off = 0
    for r in inv_rows:
        iid = r["invoice_id"]
        if not line_count[iid]:
            no_lines += 1
            continue
        if line_sum_cogs[iid] != r["cogs"]:
            cogs_off += 1
        if line_sum_ns[iid] != r["net_sales"]:
            ns_off += 1
    stats["invoices_without_lines"] = no_lines
    stats["invoices_line_cogs_ne_header"] = cogs_off
    stats["invoices_line_net_sales_ne_header"] = ns_off
    problems += cogs_off + ns_off
    return problems


def target_report(tgt: pymysql.Connection, inv_rows, line_rows) -> None:
    print("\n--- Target checks (read-only) ---")
    with tgt.cursor() as cur:
        for t in ("sales_invoices", "sales_lines"):
            if not table_exists(cur, t):
                print(f"  {t}: MISSING in target (run reports/db.py SCHEMA first)")
                continue
            cur.execute(f"SHOW COLUMNS FROM `{t}` LIKE 'line_item_id'")
            shape = "new schema" if (t == "sales_invoices" or cur.fetchone()) else "OLD run-based shape"
            cur.execute(f"SELECT COUNT(*) AS n FROM `{t}`")
            print(f"  {t}: {cur.fetchone()['n']} existing rows, {shape}")
        for t, col, rows in (
            ("customers", "customer_id", {r["customer_id"] for r in inv_rows if r["customer_id"]}),
            ("items", "item_id", {r["item_id"] for r in line_rows if r["item_id"]}),
        ):
            if not table_exists(cur, t):
                print(f"  {t}: MISSING in target; {len(rows)} referenced ids would dangle")
                continue
            cur.execute(f"SELECT `{col}` AS k FROM `{t}`")
            have = {x["k"] for x in cur.fetchall()}
            print(f"  {t}: {len(rows - have)} of {len(rows)} referenced ids not in target")


INV_SQL = """
INSERT INTO sales_invoices (
    invoice_id, invoice_number, `date`, due_date, status, customer_id, customer_name,
    salesperson_name, currency_code, exchange_rate, sub_total, discount_total,
    tax_total, total, balance, net_sales, cogs, flagged_lines
) VALUES (
    %(invoice_id)s, %(invoice_number)s, %(date)s, %(due_date)s, %(status)s, %(customer_id)s,
    %(customer_name)s, %(salesperson_name)s, %(currency_code)s, %(exchange_rate)s,
    %(sub_total)s, %(discount_total)s, %(tax_total)s, %(total)s, %(balance)s,
    %(net_sales)s, %(cogs)s, %(flagged_lines)s
) ON DUPLICATE KEY UPDATE
    invoice_number = VALUES(invoice_number), `date` = VALUES(`date`),
    due_date = VALUES(due_date), status = VALUES(status),
    customer_id = VALUES(customer_id), customer_name = VALUES(customer_name),
    salesperson_name = VALUES(salesperson_name), currency_code = VALUES(currency_code),
    exchange_rate = VALUES(exchange_rate), sub_total = VALUES(sub_total),
    discount_total = VALUES(discount_total), tax_total = VALUES(tax_total),
    total = VALUES(total), balance = VALUES(balance), net_sales = VALUES(net_sales),
    cogs = VALUES(cogs), flagged_lines = VALUES(flagged_lines)
"""

LINE_SQL = """
INSERT INTO sales_lines (
    line_item_id, invoice_id, `date`, item_id, item_name, quantity, unit, base_unit,
    conversion_rate, base_quantity, rate, item_total, net_sales, purchase_price, cogs, flag
) VALUES (
    %(line_item_id)s, %(invoice_id)s, %(date)s, %(item_id)s, %(item_name)s, %(quantity)s,
    %(unit)s, %(base_unit)s, %(conversion_rate)s, %(base_quantity)s, %(rate)s,
    %(item_total)s, %(net_sales)s, %(purchase_price)s, %(cogs)s, %(flag)s
) ON DUPLICATE KEY UPDATE
    invoice_id = VALUES(invoice_id), `date` = VALUES(`date`), item_id = VALUES(item_id),
    item_name = VALUES(item_name), quantity = VALUES(quantity), unit = VALUES(unit),
    base_unit = VALUES(base_unit), conversion_rate = VALUES(conversion_rate),
    base_quantity = VALUES(base_quantity), rate = VALUES(rate),
    item_total = VALUES(item_total), net_sales = VALUES(net_sales),
    purchase_price = VALUES(purchase_price), cogs = VALUES(cogs), flag = VALUES(flag)
"""


def apply(tgt: pymysql.Connection, inv_rows, line_rows) -> None:
    with tgt.cursor() as cur:
        for t in ("sales_invoices", "sales_lines"):
            if not table_exists(cur, t):
                raise SystemExit(f"Target table {t} is missing; create the schema first.")
        cur.execute("SHOW COLUMNS FROM sales_lines LIKE 'line_item_id'")
        if cur.fetchone() is None:
            raise SystemExit("Target sales_lines is the old run-based shape; refusing to write.")
        # customers / locations are not seeded yet, so FK references would fail.
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        for i in range(0, len(inv_rows), 1000):
            cur.executemany(INV_SQL, inv_rows[i : i + 1000])
        for i in range(0, len(line_rows), 1000):
            cur.executemany(LINE_SQL, line_rows[i : i + 1000])
        cur.execute("SET FOREIGN_KEY_CHECKS = 1")
        dates = [r["date"] for r in inv_rows]
        lo, hi = record_coverage(cur, "sales", min(dates), max(dates), "seed_sales")
        print(f"sync_coverage sales: {lo}..{hi}")
    tgt.commit()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", default="nellon_mis_dev")
    ap.add_argument("--target", default="zoho-koyson")
    ap.add_argument("--apply", action="store_true", help="write to the target (default: dry-run)")
    args = ap.parse_args()

    src = connect(args.source)
    try:
        with src.cursor() as cur:
            cur.execute("SELECT item_id FROM items")
            item_ids = {r["item_id"] for r in cur.fetchall()}
        inv_rows, line_rows, stats = build_rows(src, item_ids)
    finally:
        src.close()

    problems = validate(inv_rows, line_rows, stats)

    print(f"Source: {args.source}   Target: {args.target}   Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
    print(f"sales_invoices rows built: {len(inv_rows):,}")
    print(f"sales_lines rows built:    {len(line_rows):,}")
    for k, v in sorted(stats.items()):
        print(f"  {k}: {v:,}")
    print(f"Header-vs-line mismatches:  {problems}")
    print(f"Sample invoice: {inv_rows[0] if inv_rows else None}")
    print(f"Sample line:    {line_rows[0] if line_rows else None}")

    try:
        tgt = connect(args.target)
    except pymysql.MySQLError as e:
        print(f"\nTarget {args.target} not reachable: {e}")
        if args.apply:
            return 1
        return 0
    try:
        target_report(tgt, inv_rows, line_rows)
        if not args.apply:
            print("\n[DRY RUN COMPLETE] Nothing was written. Re-run with --apply to upsert.")
            return 0
        if problems:
            print("Refusing to apply with header/line mismatches.", file=sys.stderr)
            return 1
        apply(tgt, inv_rows, line_rows)
        print("\nCommitted.")
    except Exception:
        tgt.rollback()
        raise
    finally:
        tgt.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
