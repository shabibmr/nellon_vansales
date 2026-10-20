"""Seed purchase_docs / purchase_lines (zoho-koyson schema) from the local Zoho cache.

Source: output/cache/bills/*.json and output/cache/purchaseorders/*.json (no Zoho calls).
Target: purchase_docs and purchase_lines as defined in proposal/DB-Schema-Proposed.sql.

Usage:
    python seed_purchases_from_cache.py                       # dry-run, September 2026
    python seed_purchases_from_cache.py --from 2026-04-01 --to 2026-09-30
    python seed_purchases_from_cache.py --apply               # upsert into the target

Rules (DB-Schema-Proposed.md "Purchases"): amount is the line total less line discount
and its share of the document discount, times the document exchange rate, excluding
tax; header amount is the sum of line amounts. Draft, void and cancelled documents are
stored. Lines of a replaced document that are gone from the payload are deleted on apply.
vendors is not loaded yet, so --apply turns FK checks off for the write.
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter, defaultdict
from datetime import date
from decimal import Decimal

from seed_common import (
    BASE_DIR, connect, cents, d, doc_money, load_item_rates, load_item_units, parse_date,
    parse_dt, read_cache, record_coverage, resolve_conversion, s, table_exists, upsert_sql,
)

CACHE = BASE_DIR / "output" / "cache"
KINDS = (
    ("bill", CACHE / "bills", "bill", "bill_id", "bill_number"),
    ("purchase_order", CACHE / "purchaseorders", "purchaseorder", "purchaseorder_id", "purchaseorder_number"),
)


def build(doc_from: date, doc_to: date, units: dict, item_rates: dict):
    docs, lines, stats = [], [], Counter()
    seen_lines: set[str] = set()
    for kind, folder, key, id_field, num_field in KINDS:
        for h in read_cache(folder, key):
            dt = parse_date(h.get("date"))
            if dt is None or not (doc_from <= dt <= doc_to):
                continue
            stats[f"{kind}_docs"] += 1
            raw_lines = h.get("line_items") or []
            money = doc_money(h, raw_lines)
            doc_id = s(h.get(id_field), 40)
            flagged = 0
            built = []
            for ln, m in zip(raw_lines, money):
                lid = s(ln.get("line_item_id"), 40)
                if not lid:
                    stats["lines_without_id_skipped"] += 1
                    continue
                if lid in seen_lines:
                    stats["duplicate_line_item_id"] += 1
                    continue
                seen_lines.add(lid)
                qty = d(ln.get("quantity"))
                conv, flag = resolve_conversion(ln, units)
                iid = s(ln.get("item_id"), 40) or None
                if iid is not None and iid not in item_rates:
                    flag = (flag + "; " if flag else "") + "item_id not in items"
                    iid = None
                    stats["lines_item_not_in_items"] += 1
                if flag:
                    flagged += 1
                    stats["lines_flagged"] += 1
                if "unknown unit conversion" in flag:
                    stats["unknown_unit_conversion"] += 1
                is_bill = kind == "bill"
                built.append(
                    {
                        "line_item_id": lid, "kind": kind, "doc_id": doc_id, "date": dt,
                        "location_id": s(ln.get("location_id") or h.get("location_id"), 40) or None,
                        "location_name": s(ln.get("location_name") or h.get("location_name"), 255),
                        "item_id": iid, "item_name": s(ln.get("name") or ln.get("item_name"), 255),
                        "sku": s(ln.get("sku"), 100),
                        "account_id": s(ln.get("account_id"), 40) or None,
                        "account_name": s(ln.get("account_name"), 255),
                        "quantity": qty, "unit": s(ln.get("unit"), 40),
                        "quantity_received": Decimal("0") if is_bill else d(ln.get("quantity_received")),
                        "quantity_billed": qty if is_bill else d(ln.get("quantity_billed")),
                        "base_unit": s(ln.get("base_unit"), 40), "conversion_rate": conv,
                        "base_quantity": qty * conv, "rate": d(ln.get("rate")),
                        "line_discount": m["line_discount"], "doc_discount": m["doc_discount"],
                        "item_total": m["item_total"], "tax_amount": m["tax_amount"],
                        "amount": m["amount"],
                        "purchaseorder_item_id": s(ln.get("purchaseorder_item_id"), 40),
                        "flag": flag[:255],
                    }
                )
            if not built:
                stats["docs_without_lines"] += 1
            lines.extend(built)
            amount = sum((b["amount"] for b in built), Decimal("0"))
            expect = cents((d(h.get("sub_total")) - d(h.get("discount_total"))) * (d(h.get("exchange_rate"), "1") or 1))
            if built and abs(amount - expect) > Decimal("0.05"):
                stats["amount_vs_header_gt_5_fils"] += 1
            docs.append(
                {
                    "kind": kind, "doc_id": doc_id, "number": s(h.get(num_field), 60), "date": dt,
                    "due_date": parse_date(h.get("due_date")),
                    "expected_delivery_date": parse_date(h.get("expected_delivery_date")),
                    "status": s(h.get("status"), 30), "billed_status": s(h.get("billed_status"), 30),
                    "received_status": s(h.get("received_status"), 30),
                    "vendor_id": s(h.get("vendor_id"), 40) or None, "vendor_name": s(h.get("vendor_name"), 255),
                    "location_id": s(h.get("location_id"), 40) or None,
                    "location_name": s(h.get("location_name"), 255),
                    "currency_code": s(h.get("currency_code") or "AED", 10),
                    "exchange_rate": d(h.get("exchange_rate"), "1") or Decimal("1"),
                    "reference_number": s(h.get("reference_number"), 100),
                    "sub_total": d(h.get("sub_total")), "discount_total": d(h.get("discount_total")),
                    "tax_total": d(h.get("tax_total")), "adjustment": d(h.get("adjustment")),
                    "total": d(h.get("total")), "balance": d(h.get("balance")),
                    "amount": amount, "flagged_lines": flagged,
                    "last_modified_time": parse_dt(h.get("last_modified_time")),
                }
            )
    return docs, lines, stats


DOC_COLS = [
    "kind", "doc_id", "number", "date", "due_date", "expected_delivery_date", "status",
    "billed_status", "received_status", "vendor_id", "vendor_name", "location_id", "location_name",
    "currency_code", "exchange_rate", "reference_number", "sub_total", "discount_total", "tax_total",
    "adjustment", "total", "balance", "amount", "flagged_lines", "last_modified_time",
]
LINE_COLS = [
    "line_item_id", "kind", "doc_id", "date", "location_id", "location_name", "item_id", "item_name",
    "sku", "account_id", "account_name", "quantity", "unit", "quantity_received", "quantity_billed",
    "base_unit", "conversion_rate", "base_quantity", "rate", "line_discount", "doc_discount",
    "item_total", "tax_amount", "amount", "purchaseorder_item_id", "flag",
]


def apply(tgt, docs, lines, dfrom: date, dto: date) -> int:
    removed = 0
    with tgt.cursor() as cur:
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        cur.executemany(upsert_sql("purchase_docs", DOC_COLS, {"kind", "doc_id"}), docs)
        cur.executemany(upsert_sql("purchase_lines", LINE_COLS, {"line_item_id"}), lines)
        keep: dict[tuple, list[str]] = defaultdict(list)
        for ln in lines:
            keep[(ln["kind"], ln["doc_id"])].append(ln["line_item_id"])
        for (kind, doc_id), ids in keep.items():
            marks = ", ".join(["%s"] * len(ids))
            removed += cur.execute(
                f"DELETE FROM purchase_lines WHERE kind = %s AND doc_id = %s AND line_item_id NOT IN ({marks})",
                [kind, doc_id, *ids],
            )
        cur.execute("SET FOREIGN_KEY_CHECKS = 1")
        lo, hi = record_coverage(cur, "purchases", dfrom, dto, "seed_purchases")
        print(f"sync_coverage purchases: {lo}..{hi}")
    tgt.commit()
    return removed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--from", dest="dfrom", default="2026-09-01")
    ap.add_argument("--to", dest="dto", default="2026-09-30")
    ap.add_argument("--target", default="zoho-koyson")
    ap.add_argument("--apply", action="store_true", help="write to the target (default: dry-run)")
    args = ap.parse_args()
    dfrom, dto = parse_date(args.dfrom), parse_date(args.dto)
    if not dfrom or not dto or dfrom > dto:
        ap.error("--from / --to must be YYYY-MM-DD with from <= to")

    tgt = connect(args.target)
    try:
        with tgt.cursor() as cur:
            for t in ("purchase_docs", "purchase_lines", "item_units", "items"):
                if not table_exists(cur, t):
                    print(f"Target table {t} is missing; create the schema first.", file=sys.stderr)
                    return 1
            units, rates = load_item_units(cur), load_item_rates(cur)
        docs, lines, stats = build(dfrom, dto, units, rates)

        print(f"Window {dfrom}..{dto}   Target: {args.target}   Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
        print(f"purchase_docs rows built:  {len(docs):,}")
        print(f"purchase_lines rows built: {len(lines):,}")
        for k, v in sorted(stats.items()):
            print(f"  {k}: {v:,}")
        by = Counter((x["kind"], x["status"]) for x in docs)
        print("By kind/status:", dict(sorted(by.items())))
        print(f"Total amount (AED): {sum((x['amount'] for x in docs), Decimal('0')):,.2f}")
        non_aed = [x["doc_id"] for x in docs if x["currency_code"] != "AED"]
        print(f"Non-AED documents: {len(non_aed)}")
        with tgt.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS n FROM purchase_docs WHERE date BETWEEN %s AND %s", (dfrom, dto))
            print(f"Existing target purchase_docs in window: {cur.fetchone()['n']}")
            cur.execute("SELECT COUNT(*) AS n FROM vendors")
            n_vendors = cur.fetchone()["n"]
            print(f"vendors in target: {n_vendors}" + ("" if n_vendors else " (vendor_id links dangle until contacts are loaded)"))
        if not args.apply:
            print("\n[DRY RUN COMPLETE] Nothing was written. Re-run with --apply to upsert.")
            return 0
        if stats["duplicate_line_item_id"]:
            print("Refusing to apply: duplicate line_item_id in the cache.", file=sys.stderr)
            return 1
        removed = apply(tgt, docs, lines, dfrom, dto)
        print(f"\nCommitted {len(docs):,} documents, {len(lines):,} lines; removed {removed} stale line(s).")
    except Exception:
        tgt.rollback()
        raise
    finally:
        tgt.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
