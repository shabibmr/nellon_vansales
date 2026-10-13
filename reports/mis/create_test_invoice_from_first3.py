#!/usr/bin/env python3
"""Workflow:
1. Fetch first 3 invoices of this month itemwise.
2. Extract all items.
3. Create a new invoice with invoice number : TEST-INV-1111 ignore_auto_number_generation=true in params.
4. Get the id of customer "TEST CUSTOMER".
5. Add that as customer in JSON.
6. Use POST /invoices.
"""

from __future__ import annotations

import datetime
import json
import logging
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from zoho_client import ZohoClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("test_invoice_workflow")


def main() -> int:
    client = ZohoClient()
    today = datetime.date.today()
    first_of_month = today.replace(day=1).strftime("%Y-%m-%d")

    # -------------------------------------------------------------
    # Step 1: Fetch first 3 invoices of this month itemwise
    # -------------------------------------------------------------
    logger.info(f"Step 1: Fetching first 3 invoices of this month starting {first_of_month}...")
    list_resp = client.get(
        "/invoices",
        params={
            "date_start": first_of_month,
            "sort_column": "date",
            "sort_order": "A",
            "per_page": 3,
        },
    )
    invoices = list_resp.get("invoices", [])
    if not invoices:
        logger.error(f"No invoices found for month starting {first_of_month}")
        return 1

    logger.info(f"Found {len(invoices)} invoices in list:")
    detailed_invoices = []
    for inv in invoices:
        inv_id = str(inv["invoice_id"])
        inv_num = inv.get("invoice_number")
        logger.info(f"  - Fetching invoice detail for {inv_num} (ID: {inv_id})...")
        detail_resp = client.get(f"/invoices/{inv_id}")
        inv_detail = detail_resp.get("invoice", {})
        detailed_invoices.append(inv_detail)

    # -------------------------------------------------------------
    # Step 2: Extract all items
    # -------------------------------------------------------------
    logger.info("Step 2: Extracting all items from the 3 invoices...")
    extracted_items: list[dict[str, Any]] = []
    for inv in detailed_invoices:
        inv_num = inv.get("invoice_number")
        lines = inv.get("line_items", [])
        logger.info(f"  Invoice {inv_num} has {len(lines)} line item(s):")
        for line in lines:
            item_payload = {
                "item_id": line.get("item_id"),
                "name": line.get("name"),
                "description": line.get("description", ""),
                "rate": line.get("rate"),
                "quantity": line.get("quantity"),
                "unit": line.get("unit"),
                "tax_id": line.get("tax_id"),
            }
            if line.get("unit_conversion_id"):
                item_payload["unit_conversion_id"] = line.get("unit_conversion_id")

            extracted_items.append(item_payload)
            logger.info(
                f"    * {line.get('name')} | Qty: {line.get('quantity')} {line.get('unit')} "
                f"| Rate: {line.get('rate')} | Tax ID: {line.get('tax_id')}"
            )

    logger.info(f"Total extracted items: {len(extracted_items)}")

    # -------------------------------------------------------------
    # Step 4: Get the ID of customer 'TEST CUSTOMER'
    # -------------------------------------------------------------
    logger.info("Step 4: Looking up ID of customer 'TEST CUSTOMER'...")
    cust_resp = client.get("/contacts", params={"contact_name_contains": "Test Customer"})
    contacts = cust_resp.get("contacts", [])

    test_customer = None
    for c in contacts:
        if c.get("contact_name", "").strip().lower() == "test customer":
            test_customer = c
            break
    if not test_customer and contacts:
        test_customer = contacts[0]

    if not test_customer:
        logger.error("Customer 'TEST CUSTOMER' not found in Zoho Books")
        return 1

    customer_id = str(test_customer["contact_id"])
    customer_name = test_customer.get("contact_name")
    logger.info(f"Found customer: '{customer_name}' with ID: {customer_id}")

    # -------------------------------------------------------------
    # Step 3 & 5: Construct JSON payload
    # -------------------------------------------------------------
    logger.info("Step 3 & 5: Constructing new invoice JSON payload...")
    invoice_number = "TEST-INV-1111"
    today_str = today.strftime("%Y-%m-%d")

    new_invoice_payload: dict[str, Any] = {
        "customer_id": customer_id,
        "invoice_number": invoice_number,
        "date": today_str,
        "due_date": today_str,
        "notes": "Test invoice generated from first 3 invoices of the month.",
        "line_items": extracted_items,
    }

    print("\n--- Outgoing Invoice Payload Preview ---")
    print(json.dumps(new_invoice_payload, indent=2))

    # -------------------------------------------------------------
    # Step 6: Use POST /invoices/ with ignore_auto_number_generation=true
    # -------------------------------------------------------------
    logger.info("Step 6: Posting new invoice to POST /invoices with ignore_auto_number_generation=true...")
    post_params = {
        "ignore_auto_number_generation": "true",
        "send": "true",
    }

    try:
        create_resp = client.post("/invoices", json_data=new_invoice_payload, params=post_params)
    except Exception as e:
        logger.error(f"POST /invoices failed: {e}")
        return 2

    created_inv = create_resp.get("invoice", {})

    print("\n=================================================================")
    print(f"SUCCESS: Invoice Created! (Code: {create_resp.get('code')}, Message: {create_resp.get('message')})")
    print("=================================================================")
    print(f"  Invoice Number: {created_inv.get('invoice_number')}")
    print(f"  Invoice ID:     {created_inv.get('invoice_id')}")
    print(f"  Customer:       {created_inv.get('customer_name')} (ID: {created_inv.get('customer_id')})")
    print(f"  Date:           {created_inv.get('date')}")
    print(f"  Due Date:       {created_inv.get('due_date')}")
    print(f"  Status:         {created_inv.get('status')}")
    print(f"  SubTotal:       {created_inv.get('sub_total')} {created_inv.get('currency_code')}")
    print(f"  Tax Total:      {created_inv.get('tax_total')} {created_inv.get('currency_code')}")
    print(f"  Total:          {created_inv.get('total')} {created_inv.get('currency_code')}")
    print(f"  Line Items Count: {len(created_inv.get('line_items', []))}")
    for idx, li in enumerate(created_inv.get("line_items", []), 1):
        print(f"    {idx}. {li.get('name')}: {li.get('quantity')} {li.get('unit')} @ {li.get('rate')} -> Line Total: {li.get('item_total')}")
    if created_inv.get("invoice_url"):
        print(f"\n  Invoice URL:    {created_inv.get('invoice_url')}")
    print("=================================================================\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
