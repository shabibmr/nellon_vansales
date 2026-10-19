"""Seed customers, vendors, credit notes and debit notes (zoho-koyson schema) from the local cache.

Source: output/cache/contacts/{customers,vendors}.json, output/cache/creditnotes/*.json and
output/cache/debitnotes/*.json, written by fetch_zoho_notes_contacts.py. No Zoho calls here.

Usage:
    python seed_notes_contacts_from_cache.py                      # dry-run, September 2026
    python seed_notes_contacts_from_cache.py --cache-dir DIR      # read a different cache root
    python seed_notes_contacts_from_cache.py --apply              # upsert into the target

Money and COGS follow DB-Schema-Proposed.md. net_sales and cogs are stored positive; the
reports subtract credit notes and add debit notes. A credit-only line has cogs 0. A line with
no purchase_price uses the item master rate and is flagged. Header cogs here is the line-rule sum; reconciling
credit-note cogs to the ledger (inventory_valuation_for_credit_notes) is a separate step, not yet written.
Draft and void notes are stored.
Lines of a replaced note that are gone from the payload are deleted on apply. Rows are
written only for columns the target table really has; any gap is printed.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import date
from decimal import Decimal
from pathlib import Path

from seed_common import (
    BASE_DIR, connect, d, doc_money, line_cogs, load_item_rates, load_item_units, parse_date,
    parse_dt, read_cache, resolve_conversion, s, table_exists,
)

NOTES = {
    "credit": dict(
        folder="creditnotes", key="creditnote", id_field="creditnote_id", num_field="creditnote_number",
        head="credit_notes", line="credit_note_lines", pk="creditnote_id", disc="note_discount",
    ),
    "debit": dict(
        folder="debitnotes", key="invoice", id_field="invoice_id", num_field="invoice_number",
        head="debit_notes", line="debit_note_lines", pk="debit_note_id", disc="note_discount",
    ),
}


def build_notes(kind: str, cache: Path, dfrom: date, dto: date, units: dict, rates: dict):
    cfg = NOTES[kind]
    heads, lines, stats = [], [], Counter()
    seen: set[str] = set()
    for h in read_cache(cache / cfg["folder"], cfg["key"]):
        dt = parse_date(h.get("date"))
        if dt is None or not (dfrom <= dt <= dto):
            continue
        stats["notes"] += 1
        raw = h.get("line_items") or []
        money = doc_money(h, raw)
        note_id = s(h.get(cfg["id_field"]), 40)
        built, flagged = [], 0
        for ln, m in zip(raw, money):
            lid = s(ln.get("line_item_id"), 40)
            if not lid or lid in seen:
                stats["lines_skipped_no_or_duplicate_id"] += 1
                continue
            seen.add(lid)
            qty = d(ln.get("quantity"))
            conv, flag = resolve_conversion(ln, units)
            base_qty = qty * conv
            iid = s(ln.get("item_id"), 40) or None
            master = rates.get(iid, Decimal("0")) if iid else Decimal("0")
            if iid is not None and iid not in rates:
                flag = (flag + "; " if flag else "") + "item_id not in items"
                iid = None
            price = d(ln.get("purchase_price"))
            credit_only = bool(ln.get("is_credit_only_item"))
            cogs, cflag = line_cogs(qty, conv, base_qty, price, master, s(ln.get("base_unit"), 40), credit_only)
            if cflag:
                flag = (flag + "; " if flag else "") + cflag
            if flag:
                flagged += 1
                stats["lines_flagged"] += 1
            row = {
                "line_item_id": lid, cfg["pk"]: note_id, "date": dt,
                "invoice_id": s(ln.get("invoice_id"), 40) or None,
                "invoice_item_id": s(ln.get("invoice_item_id"), 40) or None,
                "location_id": s(ln.get("location_id") or h.get("location_id"), 40) or None,
                "location_name": s(ln.get("location_name") or h.get("location_name"), 255),
                "item_id": iid, "item_name": s(ln.get("name") or ln.get("item_name"), 255),
                "sku": s(ln.get("sku"), 100),
                "account_id": s(ln.get("account_id"), 40) or None, "account_name": s(ln.get("account_name"), 255),
                "quantity": qty, "unit": s(ln.get("unit"), 40), "base_unit": s(ln.get("base_unit"), 40),
                "conversion_rate": conv, "base_quantity": base_qty, "rate": d(ln.get("rate")),
                "line_discount": m["line_discount"], "note_discount": m["doc_discount"],
                "item_total": m["item_total"], "tax_amount": m["tax_amount"], "net_sales": m["amount"],
                "purchase_price": price, "cogs": cogs, "flag": flag[:255],
            }
            built.append(row)
        if not built:
            stats["notes_without_lines"] += 1
        lines.extend(built)
        first = built[0] if built else {}
        ref = h.get("reference_invoice") if isinstance(h.get("reference_invoice"), dict) else {}
        head = {
            cfg["pk"]: note_id,
            ("creditnote_number" if kind == "credit" else "debit_note_number"): s(h.get(cfg["num_field"]), 60),
            "date": dt, "due_date": parse_date(h.get("due_date")), "status": s(h.get("status"), 30),
            "customer_id": s(h.get("customer_id"), 40) or None, "customer_name": s(h.get("customer_name"), 255),
            "salesperson_id": s(h.get("salesperson_id"), 40) or None,
            "salesperson_name": s(h.get("salesperson_name"), 255),
            "location_id": s(h.get("location_id"), 40) or None, "location_name": s(h.get("location_name"), 255),
            "reference_number": s(h.get("reference_number"), 100),
            "reason": s(h.get("reason_for_credit_debit_note") or h.get("reason"), 255),
            "currency_code": s(h.get("currency_code") or "AED", 10),
            "exchange_rate": d(h.get("exchange_rate"), "1") or Decimal("1"),
            "sub_total": d(h.get("sub_total")), "discount_total": d(h.get("discount_total")),
            "tax_total": d(h.get("tax_total")), "shipping_charge": d(h.get("shipping_charge")),
            "adjustment": d(h.get("adjustment")), "total": d(h.get("total")), "balance": d(h.get("balance")),
            "net_sales": sum((b["net_sales"] for b in built), Decimal("0")),
            "cogs": sum((b["cogs"] for b in built), Decimal("0")),
            "flagged_lines": flagged, "last_modified_time": parse_dt(h.get("last_modified_time")),
        }
        if kind == "credit":
            head["invoice_id"] = s(h.get("invoice_id") or first.get("invoice_id"), 40) or None
            head["invoice_number"] = s(h.get("invoice_number"), 60)
        else:
            head["reference_invoice_id"] = s(h.get("reference_invoice_id") or ref.get("reference_invoice_id"), 40) or None
            head["reference_invoice_number"] = s(
                h.get("reference_invoice_number") or ref.get("reference_invoice_number"), 60
            )
        heads.append(head)
    return heads, lines, stats


def build_contacts(cache: Path, name: str, id_col: str, with_credit: bool) -> list[dict]:
    path = cache / "contacts" / f"{name}.json"
    if not path.exists():
        return []
    rows = []
    for c in json.loads(path.read_text(encoding="utf-8")).get("contacts", []):
        row = {
            id_col: s(c.get("contact_id"), 40), "contact_name": s(c.get("contact_name"), 255),
            "company_name": s(c.get("company_name"), 255), "status": s(c.get("status") or "active", 20),
            "email": s(c.get("email"), 255), "phone": s(c.get("phone") or c.get("mobile"), 50),
            "tax_treatment": s(c.get("tax_treatment"), 50), "tax_reg_no": s(c.get("tax_reg_no"), 50),
            "payment_terms": int(d(c.get("payment_terms"))), "payment_terms_label": s(c.get("payment_terms_label"), 100),
            "currency_code": s(c.get("currency_code") or "AED", 10),
            "last_modified_time": parse_dt(c.get("last_modified_time")),
        }
        if with_credit:
            row["customer_sub_type"] = s(c.get("customer_sub_type"), 50)
            row["credit_limit"] = d(c.get("credit_limit"))
        if row[id_col]:
            rows.append(row)
    return rows


def target_cols(cur, table: str) -> list[str]:
    cur.execute(f"SHOW COLUMNS FROM `{table}`")
    return [r["Field"] for r in cur.fetchall()]


def upsert(cur, table: str, rows: list[dict], pk: set[str]) -> None:
    if not rows:
        return
    have = set(target_cols(cur, table))
    cols = [c for c in rows[0] if c in have]
    dropped = [c for c in rows[0] if c not in have]
    if dropped:
        print(f"  note: {table} has no column(s) {dropped}; not written")
    sql = (
        f"INSERT INTO `{table}` ({', '.join(f'`{c}`' for c in cols)}) VALUES ({', '.join(f'%({c})s' for c in cols)}) "
        "ON DUPLICATE KEY UPDATE " + ", ".join(f"`{c}` = VALUES(`{c}`)" for c in cols if c not in pk)
    )
    cur.executemany(sql, [{c: r[c] for c in cols} for r in rows])


def apply(tgt, customers, vendors, loaded: dict) -> int:
    removed = 0
    with tgt.cursor() as cur:
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        upsert(cur, "customers", customers, {"customer_id"})
        upsert(cur, "vendors", vendors, {"vendor_id"})
        for kind, (heads, lines) in loaded.items():
            cfg = NOTES[kind]
            upsert(cur, cfg["head"], heads, {cfg["pk"]})
            upsert(cur, cfg["line"], lines, {"line_item_id"})
            keep: dict[str, list[str]] = defaultdict(list)
            for ln in lines:
                keep[ln[cfg["pk"]]].append(ln["line_item_id"])
            for note_id, ids in keep.items():
                marks = ", ".join(["%s"] * len(ids))
                removed += cur.execute(
                    f"DELETE FROM `{cfg['line']}` WHERE `{cfg['pk']}` = %s AND line_item_id NOT IN ({marks})",
                    [note_id, *ids],
                )
        cur.execute("SET FOREIGN_KEY_CHECKS = 1")
    tgt.commit()
    return removed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--from", dest="dfrom", default="2026-09-01")
    ap.add_argument("--to", dest="dto", default="2026-09-30")
    ap.add_argument("--cache-dir", type=Path, default=BASE_DIR / "output" / "cache")
    ap.add_argument("--target", default="zoho-koyson")
    ap.add_argument("--apply", action="store_true", help="write to the target (default: dry-run)")
    args = ap.parse_args()
    dfrom, dto = parse_date(args.dfrom), parse_date(args.dto)
    if not dfrom or not dto or dfrom > dto:
        ap.error("--from / --to must be YYYY-MM-DD with from <= to")

    tgt = connect(args.target)
    try:
        with tgt.cursor() as cur:
            for t in ("customers", "vendors", "credit_notes", "credit_note_lines", "debit_notes",
                      "debit_note_lines", "item_units", "items"):
                if not table_exists(cur, t):
                    print(f"Target table {t} is missing; create the schema first.", file=sys.stderr)
                    return 1
            units, rates = load_item_units(cur), load_item_rates(cur)

        customers = build_contacts(args.cache_dir, "customers", "customer_id", True)
        vendors = build_contacts(args.cache_dir, "vendors", "vendor_id", False)
        loaded, problems = {}, 0
        print(f"Window {dfrom}..{dto}   Cache: {args.cache_dir}   Target: {args.target}   "
              f"Mode: {'APPLY' if args.apply else 'DRY-RUN'}")
        print(f"customers: {len(customers):,}   vendors: {len(vendors):,}")
        if not customers or not vendors:
            print("  (contacts cache missing or empty: run fetch_zoho_notes_contacts.py first)")
        for kind in ("credit", "debit"):
            heads, lines, stats = build_notes(kind, args.cache_dir, dfrom, dto, units, rates)
            loaded[kind] = (heads, lines)
            line_ns: dict[str, Decimal] = defaultdict(Decimal)
            for ln in lines:
                line_ns[ln[NOTES[kind]["pk"]]] += ln["net_sales"]
            bad = sum(1 for h in heads if h["net_sales"] != line_ns[h[NOTES[kind]["pk"]]])
            problems += bad
            print(f"{kind} notes: {len(heads):,} headers, {len(lines):,} lines; "
                  f"net_sales {sum((h['net_sales'] for h in heads), Decimal('0')):,.2f}  "
                  f"cogs {sum((h['cogs'] for h in heads), Decimal('0')):,.2f}")
            for k, v in sorted(stats.items()):
                print(f"  {k}: {v:,}")
            print(f"  status: {dict(Counter(h['status'] for h in heads))}   header/line mismatches: {bad}")
        if not args.apply:
            print("\n[DRY RUN COMPLETE] Nothing was written. Re-run with --apply to upsert.")
            return 0
        if problems:
            print("Refusing to apply with header/line mismatches.", file=sys.stderr)
            return 1
        removed = apply(tgt, customers, vendors, loaded)
        print(f"\nCommitted. Removed {removed} stale line(s).")
    except Exception:
        tgt.rollback()
        raise
    finally:
        tgt.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
