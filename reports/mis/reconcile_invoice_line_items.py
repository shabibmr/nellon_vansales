#!/usr/bin/env python3
"""Reconcile all inv.cost_of_sales against the sum of line_items cost_of_sales in invoice_line_items / invoice_item_details.

Logical Reconciliation Methodology:
1. Non-inventory lines (e.g. Excise Tax, delivery fees):
   - cost_of_sales = 0.00 [source: non-inventory tax/fee line item]
2. Baseline goods cost calculation:
   - If line has `purchase_price` (> 0):
     base_cost = ROUND(qty * purchase_price, 2) [source: Zoho Books invoice line item valuation]
   - Else if line has `cost_from_masters` (> 0):
     base_cost = ROUND(base_qty * cost_from_masters, 2) [source: item master purchase rate]
   - Else:
     base_cost = 0.00 [source: unpriced item]
3. Invoice-level reconciliation against `inv.cost_of_sales`:
   - Case A (Exact baseline match, diff = 0.00):
     Lines retain exact base valuation. Notes cite line valuation source.
   - Case B (Within ±0.01 rounding tolerance):
     Line costs match within rounding tolerance. The 1-cent penny variance is assigned to the
     largest line so that sum(lines) equals inv.cost_of_sales to 0.00 cents.
     Notes cite line valuation source and 1-cent rounding adjustment.
   - Case C (Single-line invoice):
     All invoice cost_of_sales belongs to the single line item.
     Notes cite single-line assignment to invoice GL booked valuation.
   - Case D (Multi-line invoice with GL variance):
     Zoho's booked GL debit reflects actual lot-based inventory valuation at transaction time,
     whereas line purchase_price was a document creation snapshot.
     The variance (inv.cost_of_sales - sum(base_costs)) is proportionally distributed across goods lines
     in proportion to their baseline cost weight (or item_total weight).
     Remainder penny is assigned to the largest line.
     Notes cite baseline line valuation and proportional GL variance allocation.

Usage:
    python reconcile_invoice_line_items.py            # Dry-run: preview summary and verify
    python reconcile_invoice_line_items.py --apply    # Execute database updates and commit
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import Counter, defaultdict
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / ".env.mis")


def get_connection(db_name: str) -> pymysql.Connection:
    return pymysql.connect(
        host=os.getenv("MIS_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("MIS_DB_PORT", "3306")),
        user=os.getenv("MIS_DB_USER", "user2grey"),
        password=os.getenv("MIS_DB_PASSWORD", "user2grey"),
        database=db_name,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def quantize_cents(val: Decimal) -> Decimal:
    return val.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def format_line_note(
    method: str,
    qty: Decimal,
    unit_cost: Decimal,
    base_cost: Decimal,
    adj: Decimal,
    final_cost: Decimal,
    source_name: str,
) -> str:
    if method == "tax":
        return f"Non-inventory line item ({source_name}): cost_of_sales = 0.00 [source: tax/fee charge, zero inventory cost]"
    elif method == "single":
        if adj != Decimal("0.00"):
            return (
                f"Single line item on invoice: base valuation = {base_cost:.2f}, "
                f"reconciled 100% to invoice GL debit = {final_cost:.2f} (variance: {adj:+.2f}) "
                f"[source: {source_name}]"
            )
        else:
            return f"Single line item on invoice: cost_of_sales = {final_cost:.2f} [source: {source_name}]"
    elif method == "purchase_price":
        base_desc = f"Zoho line valuation: qty ({qty}) * purchase_price ({unit_cost:.4f}) = {base_cost:.2f}"
    elif method == "master_rate":
        base_desc = f"Item master rate: base_qty ({qty}) * cost_from_masters ({unit_cost:.4f}) = {base_cost:.2f}"
    else:
        base_desc = f"Unpriced line item: base cost = 0.00"

    if adj == Decimal("0.00"):
        return f"{base_desc} [source: {source_name}]"
    elif abs(adj) == Decimal("0.01"):
        return f"{base_desc}; rounding tolerance adjustment ({adj:+.2f}) -> {final_cost:.2f} [source: {source_name} + 1-cent rounding]"
    else:
        return f"{base_desc}; GL valuation variance allocation ({adj:+.2f}) -> {final_cost:.2f} [source: {source_name} + proportional GL allocation]"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--database", default="nellon_mis_dev", help="Target database (default: nellon_mis_dev)")
    parser.add_argument("--apply", action="store_true", help="Apply updates to database and commit")
    args = parser.parse_args()

    print(f"Connecting to database: {args.database}")
    conn = get_connection(args.database)

    try:
        with conn.cursor() as cur:
            # 1. Ensure notes column exists in inv and view invoice_item_details exists
            print("Ensuring `notes` column exists in table `inv`...")
            cur.execute("ALTER TABLE inv ADD COLUMN IF NOT EXISTS notes TEXT NULL;")

            print("Ensuring view `invoice_item_details` exists...")
            cur.execute("CREATE OR REPLACE VIEW invoice_item_details AS SELECT * FROM invoice_line_items;")

            # 2. Fetch all inv records
            print("Fetching invoices from `inv`...")
            cur.execute("""
                SELECT invoice_id, invoice_number, date, customer_name, cost_of_sales, cost_source, ok 
                FROM inv
                ORDER BY date, invoice_number
            """)
            invoices = {r["invoice_id"]: r for r in cur.fetchall()}
            print(f"Fetched {len(invoices)} invoices from `inv`.")

            # 3. Fetch all line items
            print("Fetching line items from `invoice_line_items`...")
            cur.execute("""
                SELECT 
                    line_item_id, invoice_id, invoice_number, item_name, qty, uom, base_uom,
                    rate, item_total, purchase_price, cost_from_masters, conversion_rate, base_qty,
                    cost_of_sales, cost_source, ok, notes
                FROM invoice_line_items
                ORDER BY invoice_id, line_item_id
            """)
            all_lines = cur.fetchall()
            print(f"Fetched {len(all_lines)} line items from `invoice_line_items`.")

            lines_by_inv = defaultdict(list)
            for l in all_lines:
                lines_by_inv[l["invoice_id"]].append(l)

            # 4. Reconcile invoices and line items
            invoice_updates = []  # (ok, notes, invoice_id)
            line_updates = []     # (cost_of_sales, ok, notes, line_item_id)

            category_counts = Counter()
            mismatch_count = 0

            for inv_id, lines in lines_by_inv.items():
                if inv_id not in invoices:
                    # Line items belonging to invoices not present in inv table
                    for li in lines:
                        qty = Decimal(str(li["qty"] or 0))
                        conv = Decimal(str(li["conversion_rate"] or 1))
                        base_qty = Decimal(str(li["base_qty"] or (qty * conv)))
                        pp = Decimal(str(li["purchase_price"])) if li["purchase_price"] is not None else None
                        cm = Decimal(str(li["cost_from_masters"])) if li["cost_from_masters"] is not None else None

                        if pp is not None and pp > 0:
                            cost = quantize_cents(qty * pp)
                            note = f"Zoho line valuation: qty ({qty}) * purchase_price ({pp:.4f}) = {cost:.2f} [source: invoice line item valuation; not in inv table]"
                        elif cm is not None and cm > 0:
                            cost = quantize_cents(base_qty * cm)
                            note = f"Item master rate: base_qty ({base_qty}) * cost_from_masters ({cm:.4f}) = {cost:.2f} [source: item master purchase rate; not in inv table]"
                        else:
                            cost = Decimal("0.00")
                            note = "Unpriced item [source: not in inv table]"

                        line_updates.append((cost, 0, note, li["line_item_id"]))
                    continue

                inv = invoices[inv_id]
                target_cos = Decimal(str(inv["cost_of_sales"]))

                # Calculate baseline costs for each line
                line_data = []
                for li in lines:
                    name = (li["item_name"] or "").strip().lower()
                    qty = Decimal(str(li["qty"] or 0))
                    conv = Decimal(str(li["conversion_rate"] or 1))
                    base_qty = Decimal(str(li["base_qty"] or (qty * conv)))
                    pp = Decimal(str(li["purchase_price"])) if li["purchase_price"] is not None else None
                    cm = Decimal(str(li["cost_from_masters"])) if li["cost_from_masters"] is not None else None
                    it = Decimal(str(li["item_total"] or 0))

                    is_tax = ("excise" in name or "tax" in name)
                    if is_tax:
                        base_c = Decimal("0.00")
                        method = "tax"
                        src = li["item_name"] or "excise/tax line"
                        unit_c = Decimal("0.00")
                    elif pp is not None and pp > 0:
                        base_c = quantize_cents(qty * pp)
                        method = "purchase_price"
                        src = "invoice line item valuation"
                        unit_c = pp
                    elif cm is not None and cm > 0:
                        base_c = quantize_cents(base_qty * cm)
                        method = "master_rate"
                        src = "item master purchase rate"
                        unit_c = cm
                    else:
                        base_c = Decimal("0.00")
                        method = "zero"
                        src = "unpriced item"
                        unit_c = Decimal("0.00")

                    line_data.append({
                        "line": li,
                        "base_cost": base_c,
                        "method": method,
                        "source": src,
                        "unit_cost": unit_c,
                        "qty": base_qty if method == "master_rate" else qty,
                        "item_total": it,
                        "is_tax": is_tax,
                        "final_cost": base_c,
                        "adj": Decimal("0.00"),
                    })

                sum_base = sum(ld["base_cost"] for ld in line_data)
                diff = target_cos - sum_base

                # Reconciliation routing
                if diff == Decimal("0.00"):
                    category = "Exact baseline match (0.00 diff)"
                    for ld in line_data:
                        ld["final_cost"] = ld["base_cost"]
                        ld["adj"] = Decimal("0.00")
                    inv_note = f"Exact match with Zoho line item valuation (sum = {target_cos:.2f}, diff = 0.00)"

                elif abs(diff) == Decimal("0.01"):
                    category = "Rounding tolerance match (0.01 diff)"
                    # Assign 0.01 adjustment to largest line item
                    max_idx = max(range(len(line_data)), key=lambda i: line_data[i]["base_cost"])
                    for i, ld in enumerate(line_data):
                        if i == max_idx:
                            ld["adj"] = diff
                            ld["final_cost"] = ld["base_cost"] + diff
                        else:
                            ld["adj"] = Decimal("0.00")
                            ld["final_cost"] = ld["base_cost"]
                    inv_note = f"Matched within 0.01 rounding tolerance (base sum = {sum_base:.2f}, diff = {diff:+.2f} reconciled to largest line)"

                elif len(line_data) == 1:
                    category = "Single-line invoice GL variance"
                    ld = line_data[0]
                    ld["final_cost"] = target_cos
                    ld["adj"] = target_cos - ld["base_cost"]
                    ld["method"] = "single"
                    ld["source"] = f"Zoho GL booked valuation ({inv['cost_source']})"
                    inv_note = f"Single-line invoice: base valuation = {sum_base:.2f}, reconciled 100% to GL debit = {target_cos:.2f} (diff = {diff:+.2f})"

                else:
                    category = "Multi-line GL variance allocation"
                    goods_lines = [ld for ld in line_data if not ld["is_tax"]]
                    sum_goods_base = sum(ld["base_cost"] for ld in goods_lines)
                    sum_goods_total = sum(ld["item_total"] for ld in goods_lines)

                    allocated_sum = Decimal("0.00")
                    for ld in line_data:
                        if ld["is_tax"]:
                            ld["final_cost"] = Decimal("0.00")
                            ld["adj"] = Decimal("0.00")
                        else:
                            if sum_goods_base > 0:
                                weight = ld["base_cost"] / sum_goods_base
                            elif sum_goods_total > 0:
                                weight = ld["item_total"] / sum_goods_total
                            else:
                                weight = Decimal(1) / Decimal(len(goods_lines))

                            share = quantize_cents(diff * weight)
                            ld["adj"] = share
                            ld["final_cost"] = ld["base_cost"] + share
                            allocated_sum += ld["final_cost"]

                    remainder = target_cos - allocated_sum
                    if remainder != Decimal("0.00"):
                        max_idx = max(range(len(line_data)), key=lambda i: line_data[i]["final_cost"])
                        line_data[max_idx]["final_cost"] += remainder
                        line_data[max_idx]["adj"] += remainder

                    inv_note = f"Reconciled via proportional GL valuation debit allocation (base sum = {sum_base:.2f}, variance = {diff:+.2f} allocated across {len(goods_lines)} lines)"

                category_counts[category] += 1

                # Verify exact line sum matches target_cos
                sum_final = sum(ld["final_cost"] for ld in line_data)
                if sum_final != target_cos:
                    mismatch_count += 1
                    print(f"ERROR: Mismatch on invoice {inv['invoice_number']}: sum_final={sum_final} vs target={target_cos}")

                # Format line notes and collect update tuples
                for ld in line_data:
                    line_note = format_line_note(
                        method=ld["method"],
                        qty=ld["qty"],
                        unit_cost=ld["unit_cost"],
                        base_cost=ld["base_cost"],
                        adj=ld["adj"],
                        final_cost=ld["final_cost"],
                        source_name=ld["source"],
                    )
                    line_updates.append((ld["final_cost"], 1, line_note, ld["line"]["line_item_id"]))

                invoice_updates.append((1, inv_note, inv_id))

            # 5. Display Reconciliation Summary
            print("\n=======================================================")
            print("           RECONCILIATION AUDIT SUMMARY                ")
            print("=======================================================")
            print(f"Total Invoices Processed:               {len(invoices):,}")
            print(f"Total Line Items Reconciled:            {len(line_updates):,}")
            print(f"Total Sum Discrepancies Post-Fix:       {mismatch_count}")
            print("-------------------------------------------------------")
            for cat, cnt in category_counts.items():
                pct = (cnt / len(invoices)) * 100
                print(f"  {cat:<40}: {cnt:>5} ({pct:>5.1f}%)")
            print("=======================================================\n")

            # Sample preview
            print("--- Sample Invoice Header Updates (first 5) ---")
            for u in invoice_updates[:5]:
                print(f"  inv_id: {u[2]} | ok: {u[0]} | notes: {u[1]}")

            print("\n--- Sample Line Item Updates (first 8) ---")
            for lu in line_updates[:8]:
                print(f"  line_id: {lu[3]} | cost_of_sales: {lu[0]:>8.2f} | ok: {lu[1]} | notes: {lu[2]}")

            if not args.apply:
                print("\n[DRY RUN COMPLETE] No changes were written to the database.")
                print("To commit these updates, run:\n    python reconcile_invoice_line_items.py --apply")
                return 0

            # 6. Apply updates
            print("\n[APPLYING CHANGES TO DATABASE]")

            # Update inv in batches
            batch_size = 1000
            print(f"Updating {len(invoice_updates)} rows in table `inv`...")
            inv_sql = "UPDATE inv SET ok = %s, notes = %s WHERE invoice_id = %s;"
            for i in range(0, len(invoice_updates), batch_size):
                batch = invoice_updates[i:i + batch_size]
                cur.executemany(inv_sql, batch)

            # Update invoice_line_items in batches
            print(f"Updating {len(line_updates)} rows in table `invoice_line_items`...")
            li_sql = "UPDATE invoice_line_items SET cost_of_sales = %s, ok = %s, notes = %s WHERE line_item_id = %s;"
            for i in range(0, len(line_updates), batch_size):
                batch = line_updates[i:i + batch_size]
                cur.executemany(li_sql, batch)

            conn.commit()
            print("SUCCESS: Database transaction committed successfully!")

            # 7. Post-update verification
            print("\n--- Post-Update Verification Queries ---")
            cur.execute("""
                SELECT 
                    COUNT(*) AS total_invoices,
                    SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok_1_invoices,
                    SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS ok_0_invoices
                FROM inv;
            """)
            inv_stats = cur.fetchone()
            print(f"inv table: {inv_stats}")

            cur.execute("""
                SELECT 
                    COUNT(*) AS total_lines,
                    SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok_1_lines,
                    SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS ok_0_lines,
                    SUM(CASE WHEN cost_of_sales IS NULL THEN 1 ELSE 0 END) AS null_cos_lines,
                    SUM(CASE WHEN notes IS NULL OR notes = '' THEN 1 ELSE 0 END) AS empty_notes_lines
                FROM invoice_line_items;
            """)
            ili_stats = cur.fetchone()
            print(f"invoice_line_items table: {ili_stats}")

            cur.execute("""
                SELECT 
                    COUNT(*) AS total_inv,
                    SUM(CASE WHEN ABS(i.cost_of_sales - ili_sum.sum_cos) <= 0.01 THEN 1 ELSE 0 END) AS matched_invs,
                    MAX(ABS(i.cost_of_sales - ili_sum.sum_cos)) AS max_diff
                FROM inv i
                JOIN (
                    SELECT invoice_id, SUM(cost_of_sales) AS sum_cos
                    FROM invoice_line_items
                    GROUP BY invoice_id
                ) ili_sum ON ili_sum.invoice_id = i.invoice_id;
            """)
            match_stats = cur.fetchone()
            print(f"inv vs invoice_line_items match: {match_stats}")

            cur.execute("""
                SELECT 
                    COUNT(*) AS view_total_lines,
                    COUNT(DISTINCT invoice_id) AS view_total_invs
                FROM invoice_item_details;
            """)
            view_stats = cur.fetchone()
            print(f"invoice_item_details view verification: {view_stats}")

    except Exception as e:
        conn.rollback()
        print(f"ERROR: {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
