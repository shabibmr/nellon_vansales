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

from common.account_postings import to_row as postings_to_row
from common.seed_common import (
    BASE_DIR, connect, d, load_item_rates, load_item_units,
    parse_date, parse_dt, record_coverage, s, table_exists, upsert_sql,
)
from common.zoho_client import ZohoClient
from zoho_sync.store_db import DbStore
from zoho_sync.cogs import COS_ACCOUNT_ID, apply_cogs, load_invoice_postings
from zoho_sync.mapping import build_sales_lines

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


def sync_recent_gl_journals(conn: pymysql.Connection, client: ZohoClient, dfrom: str, dto: str) -> int:
    """Fetch recent Cost of Sales postings and upsert into gl_journals."""
    print(f"Syncing GL inventory valuations from Zoho for {dfrom}..{dto}...")
    res = client.get("/chartofaccounts/transactions", params={
        "account_id": COS_ACCOUNT_ID,
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
        payload = dict(t)
        if not payload.get("account_id"):
            payload["account_id"] = COS_ACCOUNT_ID
        rows.append(postings_to_row(payload, page_ctx))

    cols = list(rows[0].keys())
    sql = upsert_sql("gl_journals", cols, {"account_id", "categorized_transaction_id"})

    with conn.cursor() as cur:
        cur.executemany(sql, rows)
    conn.commit()
    print(f"Upserted {len(rows)} Cost of Sales postings into gl_journals.")
    return len(rows)


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
        raw_by_id = {s(ln.get("line_item_id"), 40): ln for ln in raw_lines if s(ln.get("line_item_id"), 40)}

        inv_date = parse_date(h.get("date"))
        cid = s(h.get("customer_id"), 40) or None
        if cid and cid not in cust_ids:
            cid = None
            stats["invoice_customer_not_in_customers"] += 1

        skipped = sum(1 for ln in raw_lines if not s(ln.get("line_item_id"), 40))
        if skipped:
            stats["lines_without_id_skipped"] += skipped

        built_lines = build_sales_lines(h, raw_lines, units, rates)
        flagged_count = 0
        for bl in built_lines:
            iid_line = bl["item_id"]
            if iid_line and iid_line not in item_ids:
                stats["line_item_not_in_items"] += 1
                bl["item_id"] = None
                item_flag = "item_id not in items"
                bl["flag"] = f"{bl['flag']}; {item_flag}" if bl["flag"] else item_flag
                bl["flag"] = bl["flag"][:255]
            if bl["flag"]:
                flagged_count += 1
                stats["lines_flagged"] += 1

        postings_total = gl_cogs_map.get(iid)
        if postings_total is not None:
            stats["invoices_reconciled_to_gl"] += 1
        else:
            stats["invoices_unreconciled_line_sum_cogs"] += 1
        header_cogs, allocated = apply_cogs(s(h.get("status"), 30), built_lines, postings_total)
        for bl, alloc in zip(built_lines, allocated):
            bl["cogs"] = alloc

        built_ili = []
        for bl in built_lines:
            ln = raw_by_id.get(bl["line_item_id"], {})
            built_ili.append({
                "line_item_id": bl["line_item_id"],
                "invoice_id": iid,
                "Invoice#": s(h.get("invoice_number"), 60),
                "invoice_number": s(h.get("invoice_number"), 60),
                "date": inv_date,
                "item_id": bl["item_id"],
                "item_name": bl["item_name"],
                "qty": bl["quantity"],
                "uom": bl["unit"],
                "base_uom": bl["base_unit"],
                "rate": bl["rate"],
                "sales_rate": d(ln.get("sales_rate")),
                "item_total": bl["item_total"],
                "purchase_price": bl["purchase_price"],
                "conversion_rate": bl["conversion_rate"],
                "cost_of_sales": bl["cogs"],
                "cost_source": s(ln.get("cost_source"), 50),
            })

        header_net_sales = sum((bl["net_sales"] for bl in built_lines), Decimal("0"))

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

        gl_cogs_map = load_invoice_postings(DbStore(conn), COS_ACCOUNT_ID, missing_ids)

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
