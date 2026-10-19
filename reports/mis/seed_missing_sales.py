"""Seed missing sales invoices and lines into zoho-koyson from output/cache/invoices/.

1. Fetches GL inventory valuations from Zoho Books for recent dates (Oct 17-19) into gl_journals.
2. Reads cached invoice JSONs for missing invoices.
3. Computes net_sales (via seed_common.doc_money) and COGS (reconciled to gl_journals when available).
4. Upserts into zoho-koyson:
   - sales_invoices
   - sales_lines
   - invoice_line_items
5. Updates sync_coverage table.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

from seed_common import (
    BASE_DIR, cents, connect, d, doc_money, line_cogs, load_item_rates, load_item_units,
    parse_date, parse_dt, prorate, record_coverage, resolve_conversion, s, table_exists,
)
from zoho_client import ZohoClient

CACHE_DIR = BASE_DIR / "output" / "cache" / "invoices"

SI_COLS = [
    "invoice_id", "invoice_number", "date", "due_date", "status",
    "customer_id", "customer_name", "salesperson_id", "salesperson_name",
    "location_id", "location_name", "currency_code", "exchange_rate",
    "sub_total", "discount_total", "tax_total", "shipping_charge", "adjustment",
    "total", "balance", "net_sales", "cogs", "flagged_lines", "last_modified_time",
]

SL_COLS = [
    "line_item_id", "invoice_id", "date", "location_id", "location_name",
    "item_id", "item_name", "sku", "account_id", "account_name",
    "quantity", "unit", "base_unit", "conversion_rate", "base_quantity",
    "rate", "line_discount", "invoice_discount", "item_total", "tax_amount",
    "net_sales", "purchase_price", "cogs", "flag",
]

ILI_COLS = [
    "line_item_id", "invoice_id", "Invoice#", "invoice_number", "date",
    "item_id", "item_name", "qty", "uom", "base_uom",
    "rate", "sales_rate", "item_total", "purchase_price",
    "conversion_rate", "cost_of_sales", "cost_source",
]


def upsert_sql(table: str, cols: list[str], pk: str) -> str:
    upd = ", ".join(f"`{c}` = VALUES(`{c}`)" for c in cols if c != pk)
    return (
        f"INSERT INTO `{table}` ({', '.join(f'`{c}`' for c in cols)}) "
        f"VALUES ({', '.join(f'%({c})s' for c in cols)}) "
        f"ON DUPLICATE KEY UPDATE {upd}"
    )


def sync_recent_gl_journals(conn: pymysql.Connection, client: ZohoClient, dfrom: str, dto: str) -> int:
    """Fetch recent Cost of Sales postings and upsert into gl_journals."""
    print(f"Syncing GL inventory valuations from Zoho for {dfrom}..{dto}...")
    res = client.get("/chartofaccounts/transactions", params={
        "account_id": "3331482000000034003",
        "date_start": dfrom,
        "date_end": dto,
        "per_page": 200,
    })
    txs = res.get("transactions", [])
    if not txs:
        return 0

    page_ctx = {"account_name": "Cost of Sales - Nellon", "account_code": "5.1.1000"}
    rows = []
    for t in txs:
        dr = float(t.get("debit_amount") or 0.0)
        cr = float(t.get("credit_amount") or 0.0)
        rows.append({
            "account_id": "3331482000000034003",
            "categorized_transaction_id": s(t.get("categorized_transaction_id"), 40),
            "account_name": page_ctx["account_name"],
            "account_code": page_ctx["account_code"],
            "transaction_id": s(t.get("transaction_id"), 40),
            "transaction_type": s(t.get("transaction_type"), 60),
            "transaction_type_formatted": s(t.get("transaction_type_formatted"), 120),
            "transaction_date": t.get("transaction_date") or None,
            "entry_number": s(t.get("entry_number"), 80),
            "reference_number": s(t.get("reference_number"), 120),
            "customer_id": s(t.get("customer_id"), 40),
            "payee": s(t.get("payee"), 255),
            "description": s(t.get("description"), 1000),
            "debit_or_credit": s(t.get("debit_or_credit"), 10),
            "debit_amount": dr,
            "credit_amount": cr,
            "amount": round(dr - cr, 2),
            "fcy_debit_amount": float(t.get("fcy_debit_amount") or 0.0),
            "fcy_credit_amount": float(t.get("fcy_credit_amount") or 0.0),
            "currency_id": s(t.get("currency_id"), 40),
            "currency_code": s(t.get("currency_code"), 10),
            "offset_account_name": s(t.get("offset_account_name"), 255),
            "raw_json": json.dumps(t, separators=(",", ":")),
        })

    cols = list(rows[0].keys())
    upd = ", ".join(f"`{c}` = VALUES(`{c}`)" for c in cols if c not in ("account_id", "categorized_transaction_id"))
    sql = f"INSERT INTO gl_journals ({', '.join(f'`{c}`' for c in cols)}) VALUES ({', '.join(f'%({c})s' for c in cols)}) ON DUPLICATE KEY UPDATE {upd}"

    with conn.cursor() as cur:
        cur.executemany(sql, rows)
    conn.commit()
    print(f"Upserted {len(rows)} Cost of Sales postings into gl_journals.")
    return len(rows)


def load_gl_cogs(conn: pymysql.Connection) -> dict[str, Decimal]:
    """Return map of invoice_id -> sum of GL inventory valuation amounts."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT transaction_id, SUM(amount) AS cogs
            FROM gl_journals
            WHERE transaction_type = 'inventory_valuation_for_invoice'
            GROUP BY transaction_id
        """)
        return {r["transaction_id"]: cents(d(r["cogs"])) for r in cur.fetchall()}


def build_invoice_rows(
    invoice_ids: list[str],
    units: dict,
    rates: dict,
    gl_cogs_map: dict[str, Decimal],
    cust_ids: set[str],
    item_ids: set[str],
) -> tuple[list[dict], list[dict], list[dict], Counter]:
    inv_rows = []
    line_rows = []
    ili_rows = []
    stats = Counter()

    for iid in invoice_ids:
        fpath = CACHE_DIR / f"{iid}.json"
        if not fpath.exists():
            print(f"Warning: Cache file {fpath} does not exist! Skipping.", file=sys.stderr)
            stats["cache_files_missing"] += 1
            continue

        with open(fpath, encoding="utf-8") as f:
            data = json.load(f)

        h = data.get("invoice", data)
        raw_lines = h.get("line_items") or []
        money = doc_money(h, raw_lines)

        inv_date = parse_date(h.get("date"))
        cid = s(h.get("customer_id"), 40) or None
        if cid and cid not in cust_ids:
            cid = None
            stats["invoice_customer_not_in_customers"] += 1

        built_lines = []
        built_ili = []
        flagged_count = 0

        # Pass 1: compute line baseline money & COGS
        for ln, m in zip(raw_lines, money):
            lid = s(ln.get("line_item_id"), 40)
            if not lid:
                stats["lines_without_id_skipped"] += 1
                continue

            qty = d(ln.get("quantity"))
            conv, conv_flag = resolve_conversion(ln, units)
            base_qty = qty * conv

            iid_line = s(ln.get("item_id"), 40) or None
            item_flag = ""
            if iid_line and iid_line not in item_ids:
                item_flag = "item_id not in items"
                stats["line_item_not_in_items"] += 1
                iid_line = None

            unit_price = d(ln.get("purchase_price"))
            m_rate = rates.get(iid_line, Decimal("0")) if iid_line else Decimal("0")
            base_unit = s(ln.get("base_unit"), 40)

            cogs_val, c_flag = line_cogs(
                qty=qty, conv=conv, base_qty=base_qty,
                price=unit_price, master_rate=m_rate, base_unit=base_unit
            )

            flags = [f for f in [conv_flag, item_flag, c_flag] if f]
            flag_str = "; ".join(flags)
            if flag_str:
                flagged_count += 1
                stats["lines_flagged"] += 1

            built_lines.append({
                "line_item_id": lid,
                "invoice_id": iid,
                "date": inv_date,
                "location_id": s(ln.get("location_id") or h.get("location_id"), 40) or None,
                "location_name": s(ln.get("location_name") or h.get("location_name"), 255),
                "item_id": iid_line,
                "item_name": s(ln.get("name") or ln.get("item_name") or ln.get("description"), 255),
                "sku": s(ln.get("sku"), 100),
                "account_id": s(ln.get("account_id"), 40) or None,
                "account_name": s(ln.get("account_name"), 255),
                "quantity": qty,
                "unit": s(ln.get("unit"), 40),
                "base_unit": base_unit,
                "conversion_rate": conv,
                "base_quantity": base_qty,
                "rate": d(ln.get("rate")),
                "line_discount": m["line_discount"],
                "invoice_discount": m["doc_discount"],
                "item_total": m["item_total"],
                "tax_amount": m["tax_amount"],
                "net_sales": m["amount"],
                "purchase_price": unit_price,
                "baseline_cogs": cogs_val,
                "cogs": cogs_val,
                "flag": flag_str[:255],
            })

            built_ili.append({
                "line_item_id": lid,
                "invoice_id": iid,
                "Invoice#": s(h.get("invoice_number"), 60),
                "invoice_number": s(h.get("invoice_number"), 60),
                "date": inv_date,
                "item_id": iid_line,
                "item_name": s(ln.get("name") or ln.get("item_name") or ln.get("description"), 255),
                "qty": qty,
                "uom": s(ln.get("unit"), 40),
                "base_uom": base_unit,
                "rate": d(ln.get("rate")),
                "sales_rate": d(ln.get("sales_rate")),
                "item_total": m["item_total"],
                "purchase_price": unit_price,
                "conversion_rate": conv,
                "cost_of_sales": cogs_val,
                "cost_source": s(ln.get("cost_source"), 50),
            })

        # Reconcile header COGS and line COGS
        header_net_sales = sum((bl["net_sales"] for bl in built_lines), Decimal("0"))
        baseline_cogs_sum = sum((bl["baseline_cogs"] for bl in built_lines), Decimal("0"))

        if iid in gl_cogs_map:
            gl_total_cogs = gl_cogs_map[iid]
            stats["invoices_reconciled_to_gl"] += 1
            header_cogs = gl_total_cogs
            if len(built_lines) == 1:
                built_lines[0]["cogs"] = gl_total_cogs
                built_ili[0]["cost_of_sales"] = gl_total_cogs
            elif len(built_lines) > 1:
                weights = [bl["baseline_cogs"] for bl in built_lines]
                if sum(weights) <= 0:
                    weights = [bl["net_sales"] for bl in built_lines]
                allocated = prorate(gl_total_cogs, weights)
                for bl, ili, alloc in zip(built_lines, built_ili, allocated):
                    bl["cogs"] = alloc
                    ili["cost_of_sales"] = alloc
        else:
            stats["invoices_unreconciled_line_sum_cogs"] += 1
            header_cogs = baseline_cogs_sum

        inv_rows.append({
            "invoice_id": iid,
            "invoice_number": s(h.get("invoice_number"), 60),
            "date": inv_date,
            "due_date": parse_date(h.get("due_date")),
            "status": s(h.get("status"), 30),
            "customer_id": cid,
            "customer_name": s(h.get("customer_name"), 255),
            "salesperson_id": s(h.get("salesperson_id"), 40) or None,
            "salesperson_name": s(h.get("salesperson_name"), 255),
            "location_id": s(h.get("location_id"), 40) or None,
            "location_name": s(h.get("location_name"), 255),
            "currency_code": s(h.get("currency_code") or "AED", 10),
            "exchange_rate": d(h.get("exchange_rate"), "1") or Decimal("1"),
            "sub_total": d(h.get("sub_total")),
            "discount_total": d(h.get("discount_total")),
            "tax_total": d(h.get("tax_total")),
            "shipping_charge": d(h.get("shipping_charge")),
            "adjustment": d(h.get("adjustment")),
            "total": d(h.get("total")),
            "balance": d(h.get("balance")),
            "net_sales": header_net_sales,
            "cogs": header_cogs,
            "flagged_lines": flagged_count,
            "last_modified_time": parse_dt(h.get("last_modified_time")),
        })

        line_rows.extend(built_lines)
        ili_rows.extend(built_ili)

    return inv_rows, line_rows, ili_rows, stats


def apply_seed(conn: pymysql.Connection, inv_rows: list[dict], line_rows: list[dict], ili_rows: list[dict]) -> None:
    with conn.cursor() as cur:
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")

        # 1. sales_invoices
        cur.executemany(upsert_sql("sales_invoices", SI_COLS, "invoice_id"), inv_rows)

        # 2. sales_lines
        cur.executemany(upsert_sql("sales_lines", SL_COLS, "line_item_id"), line_rows)

        # 3. invoice_line_items (if table exists)
        if table_exists(cur, "invoice_line_items"):
            cur.executemany(upsert_sql("invoice_line_items", ILI_COLS, "line_item_id"), ili_rows)

        cur.execute("SET FOREIGN_KEY_CHECKS = 1")

        # 4. update sync_coverage
        dates = [r["date"] for r in inv_rows if r.get("date")]
        if dates:
            lo, hi = record_coverage(cur, "sales", min(dates), max(dates), "seed_sales")
            print(f"Updated sync_coverage for sales: {lo}..{hi}")

    conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--from", dest="dfrom", default="2026-10-01")
    parser.add_argument("--to", dest="dto", default="2026-10-19")
    parser.add_argument("--apply", action="store_true", help="Commit to zoho-koyson (default: dry run)")
    args = parser.parse_args()

    conn = connect("zoho-koyson")
    client = ZohoClient()

    try:
        # Step 1: Sync recent GL postings so gl_journals has latest valuation records
        if args.apply:
            sync_recent_gl_journals(conn, client, "2026-10-17", args.dto)

        # Step 2: Identify missing invoices in zoho-koyson
        with conn.cursor() as cur:
            cur.execute("SELECT invoice_id FROM sales_invoices WHERE date >= %s", (args.dfrom,))
            existing_ids = {r["invoice_id"] for r in cur.fetchall()}
            units = load_item_units(cur)
            rates = load_item_rates(cur)
            cur.execute("SELECT customer_id FROM customers")
            cust_ids = {r["customer_id"] for r in cur.fetchall()}
            cur.execute("SELECT item_id FROM items")
            item_ids = {r["item_id"] for r in cur.fetchall()}

        # Load GL COGS map
        gl_cogs_map = load_gl_cogs(conn)

        # List all Zoho invoices in range
        zoho_invoices = []
        page = 1
        while True:
            res = client.get("/invoices", params={
                "date_start": args.dfrom,
                "date_end": args.dto,
                "page": page,
                "per_page": 200,
                "sort_column": "date"
            })
            zoho_invoices.extend(res.get("invoices", []))
            context = res.get("page_context", {})
            if not context.get("has_more_page"):
                break
            page += 1

        missing_ids = [inv["invoice_id"] for inv in zoho_invoices if inv["invoice_id"] not in existing_ids]
        print(f"Found {len(missing_ids)} missing invoices for {args.dfrom}..{args.dto}.")

        if not missing_ids:
            print("No missing invoices to seed.")
            return 0

        # Step 3: Build rows
        inv_rows, line_rows, ili_rows, stats = build_invoice_rows(
            missing_ids, units, rates, gl_cogs_map, cust_ids, item_ids
        )

        print("\n--- Summary of Prepared Rows ---")
        print(f"Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
        print(f"sales_invoices rows:   {len(inv_rows)}")
        print(f"sales_lines rows:      {len(line_rows)}")
        print(f"invoice_line_items:    {len(ili_rows)}")
        for k, v in sorted(stats.items()):
            print(f"  {k}: {v}")

        total_net_sales = sum(r["net_sales"] for r in inv_rows)
        total_cogs = sum(r["cogs"] for r in inv_rows)
        print(f"Total Net Sales (AED): {total_net_sales:,.2f}")
        print(f"Total COGS (AED):      {total_cogs:,.2f}")

        # Verification of line sum = header sum
        line_ns = defaultdict(Decimal)
        line_cg = defaultdict(Decimal)
        for ln in line_rows:
            line_ns[ln["invoice_id"]] += ln["net_sales"]
            line_cg[ln["invoice_id"]] += ln["cogs"]

        mismatches = 0
        for r in inv_rows:
            iid = r["invoice_id"]
            if line_ns[iid] != r["net_sales"]:
                mismatches += 1
                print(f"Net sales mismatch for {r['invoice_number']}: head={r['net_sales']} lines={line_ns[iid]}")
            if line_cg[iid] != r["cogs"]:
                mismatches += 1
                print(f"COGS mismatch for {r['invoice_number']}: head={r['cogs']} lines={line_cg[iid]}")

        print(f"Header vs Line mismatches: {mismatches}")

        if not args.apply:
            print("\n[DRY RUN COMPLETE] Run with --apply to commit to zoho-koyson.")
            return 0

        if mismatches > 0:
            print("Refusing to apply due to header/line mismatches!", file=sys.stderr)
            return 1

        apply_seed(conn, inv_rows, line_rows, ili_rows)
        print("\nSuccessfully seeded zoho-koyson database!")

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
