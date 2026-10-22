#!/usr/bin/env python3
"""Create a test invoice in Zoho Books: TEST-INV-1111.

Requirements:
- Invoice number: TEST-INV-1111
- Customer: 'Test Customer' (Zoho contact_id: 3331482000182087001)
- Line items: Top 10 most sold items from last week (via GET /reports/salesbyitem)
- Saves the invoice via POST /invoices with ignore_auto_number_generation=true
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from common.zoho_client import ZohoClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("create_test_invoice")

DEFAULT_TAX_ID = "3331482000000075238"  # UAE Standard Rate (5%)


def get_test_customer(client: ZohoClient, customer_name: str = "Test Customer") -> dict[str, Any]:
    """Find the contact record for Test Customer."""
    logger.info(f"Looking up customer '{customer_name}'...")
    res = client.get("/contacts", params={"contact_name_contains": customer_name})
    contacts = res.get("contacts", [])
    
    # Exact match first
    for c in contacts:
        if c.get("contact_name", "").strip().lower() == customer_name.lower():
            logger.info(f"Matched customer: {c.get('contact_name')} (ID: {c.get('contact_id')})")
            return c

    # Prefix/contains fallback
    if contacts:
        c = contacts[0]
        logger.info(f"Matched customer: {c.get('contact_name')} (ID: {c.get('contact_id')})")
        return c

    raise ValueError(f"Could not find customer '{customer_name}' in Zoho Books")


def get_top_sold_items_last_week(
    client: ZohoClient,
    limit: int = 10,
    from_date: str | None = None,
    to_date: str | None = None,
) -> list[dict[str, Any]]:
    """Retrieve top N items sold in the previous week from Zoho Books."""
    today = datetime.date.today()
    if not to_date or not from_date:
        # Default to previous Monday - Sunday (or past 7 days)
        # If today is Tuesday (weekday 1):
        # Last week end = today - 1 day (e.g. yesterday)
        # Last week start = today - 8 days
        end_dt = today - datetime.timedelta(days=1)
        start_dt = today - datetime.timedelta(days=8)
        from_date = start_dt.strftime("%Y-%m-%d")
        to_date = end_dt.strftime("%Y-%m-%d")

    logger.info(f"Fetching sales by item report for range {from_date} to {to_date}...")
    res = client.get("/reports/salesbyitem", params={"from_date": from_date, "to_date": to_date})
    sales = res.get("sales", [])

    valid_sales = [s for s in sales if s.get("item_id")]
    if not valid_sales:
        raise ValueError(f"No item sales found between {from_date} and {to_date}")

    # Sort descending by quantity_sold
    sorted_sales = sorted(valid_sales, key=lambda x: float(x.get("quantity_sold", 0)), reverse=True)
    top_items = sorted_sales[:limit]
    logger.info(f"Found top {len(top_items)} items sold:")
    for idx, item in enumerate(top_items, 1):
        logger.info(
            f"  {idx}. {item.get('item_name')} (ID: {item.get('item_id')}) "
            f"- Qty Sold: {item.get('quantity_sold')} {item.get('unit', '')}"
        )

    return top_items


def build_line_items(client: ZohoClient, top_sales: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Fetch item master records and prepare line item payloads."""
    line_items: list[dict[str, Any]] = []

    for s in top_sales:
        item_id = str(s["item_id"])
        item_master = client.get(f"/items/{item_id}").get("item", {})
        
        rate = float(item_master.get("rate") or s.get("average_price") or 0.0)
        tax_id = item_master.get("tax_id") or DEFAULT_TAX_ID
        unit = item_master.get("unit") or s.get("unit") or "pcs"
        item_name = item_master.get("name") or s.get("item_name")

        line_items.append({
            "item_id": item_id,
            "name": item_name,
            "rate": round(rate, 2),
            "quantity": 1.0,  # 1 unit of each top selling item for the test invoice
            "unit": unit,
            "tax_id": tax_id,
        })

    return line_items


def create_invoice(
    client: ZohoClient,
    customer_id: str,
    invoice_number: str,
    line_items: list[dict[str, Any]],
    date_str: str | None = None,
) -> dict[str, Any]:
    """Create invoice with custom invoice_number via POST /invoices."""
    today_str = date_str or datetime.date.today().strftime("%Y-%m-%d")

    payload: dict[str, Any] = {
        "customer_id": customer_id,
        "invoice_number": invoice_number,
        "date": today_str,
        "due_date": today_str,
        "notes": f"Automated Test Invoice ({invoice_number}) with Top 10 Sold Items",
        "line_items": line_items,
    }

    params = {
        "ignore_auto_number_generation": "true",
    }

    logger.info(f"Posting invoice '{invoice_number}' with {len(line_items)} line items to Zoho Books...")
    response = client.post("/invoices", json_data=payload, params=params)
    return response


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a test invoice with top 10 sold items.")
    parser.add_argument("--invoice-number", default="TEST-INV-1111", help="Invoice number (default: TEST-INV-1111)")
    parser.add_argument("--customer-name", default="Test Customer", help="Customer name (default: 'Test Customer')")
    parser.add_argument("--from-date", help="Start date for sales report (YYYY-MM-DD)")
    parser.add_argument("--to-date", help="End date for sales report (YYYY-MM-DD)")
    parser.add_argument("--dry-run", action="store_true", help="Build and preview invoice payload without saving")

    args = parser.parse_args()
    client = ZohoClient()

    # 1. Test Customer
    customer = get_test_customer(client, args.customer_name)
    customer_id = str(customer["contact_id"])

    # 2. Top 10 items last week
    top_items = get_top_sold_items_last_week(
        client, limit=10, from_date=args.from_date, to_date=args.to_date
    )

    # 3. Assemble Line Items
    line_items = build_line_items(client, top_items)

    invoice_payload = {
        "customer_id": customer_id,
        "customer_name": customer.get("contact_name"),
        "invoice_number": args.invoice_number,
        "date": datetime.date.today().strftime("%Y-%m-%d"),
        "line_items": line_items,
    }

    if args.dry_run:
        logger.info("[Dry Run] Payload prepared:")
        print(json.dumps(invoice_payload, indent=2))
        return 0

    # 4. Save Invoice
    res = create_invoice(client, customer_id, args.invoice_number, line_items)
    inv = res.get("invoice", {})

    print("\n=======================================================")
    print(f"SUCCESS: Invoice Created! (Code: {res.get('code')}, Message: {res.get('message')})")
    print("=======================================================")
    print(f"  Invoice Number: {inv.get('invoice_number')}")
    print(f"  Invoice ID:     {inv.get('invoice_id')}")
    print(f"  Customer:       {inv.get('customer_name')} (ID: {inv.get('customer_id')})")
    print(f"  Date:           {inv.get('date')}")
    print(f"  Due Date:       {inv.get('due_date')}")
    print(f"  Status:         {inv.get('status')}")
    print(f"  SubTotal:       {inv.get('sub_total')} {inv.get('currency_code')}")
    print(f"  Tax Total:      {inv.get('tax_total')} {inv.get('currency_code')}")
    print(f"  Total:          {inv.get('total')} {inv.get('currency_code')}")
    print(f"  Line Items ({len(inv.get('line_items', []))} items):")
    for idx, li in enumerate(inv.get("line_items", []), 1):
        print(f"    {idx}. {li.get('name')}: {li.get('quantity')} {li.get('unit')} @ {li.get('rate')} (Tax: {li.get('tax_name')}) -> Total: {li.get('item_total')}")
    if inv.get("invoice_url"):
        print(f"\n  Invoice URL:    {inv.get('invoice_url')}")
    print("=======================================================\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
