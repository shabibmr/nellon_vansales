#!/usr/bin/env python3
"""Zoho Books API - Get Invoice by Number and Send Back (Update/Sync).

This script performs the following workflow:
1. Authenticates with Zoho Books v3 REST API using OAuth 2.0 (via .env_zoho).
2. Searches for the invoice by number: GET /invoices?invoice_number=SMR-INV-00463.
3. Retrieves the complete invoice document: GET /invoices/{invoice_id}.
4. Sanitizes / formats the invoice JSON to match Zoho Books' mutable payload
   schema (stripping read-only and calculated fields like total, balance,
   status, contact_category, sales_channel, etc.).
5. Sends the JSON back to Zoho Books via PUT /invoices/{invoice_id}.

Usage:
    .venv/bin/python get_and_send_invoice.py
    .venv/bin/python get_and_send_invoice.py --invoice-number SMR-INV-00463
    .venv/bin/python get_and_send_invoice.py --dry-run
    .venv/bin/python get_and_send_invoice.py --send-raw   # To test Zoho's response to unmodified raw JSON
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from zoho_client import ZohoClient

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("zoho_invoice_sync")


def get_invoice_by_number(client: ZohoClient, invoice_number: str) -> dict[str, Any]:
    """Retrieve invoice by number using GET /invoices and GET /invoices/{id}."""
    logger.info(f"Searching for invoice '{invoice_number}' via GET /invoices ...")
    search_resp = client.get("/invoices", params={"invoice_number": invoice_number})
    invoices = search_resp.get("invoices", [])

    if not invoices:
        raise ValueError(f"No invoice found with invoice_number='{invoice_number}'")

    matched = invoices[0]
    invoice_id = matched["invoice_id"]
    logger.info(f"Found invoice '{invoice_number}' with ID: {invoice_id} (Status: {matched.get('status')}, Total: {matched.get('total')})")

    logger.info(f"Fetching full invoice details via GET /invoices/{invoice_id} ...")
    detail_resp = client.get(f"/invoices/{invoice_id}")
    invoice_data = detail_resp.get("invoice")

    if not invoice_data:
        raise ValueError(f"Empty invoice object returned for invoice_id={invoice_id}")

    return invoice_data


def prepare_invoice_update_payload(raw: dict[str, Any]) -> dict[str, Any]:
    """Convert a GET invoice response into a valid PUT /invoices/{id} update payload.

    Zoho Books returns ~200 fields on GET, including read-only and computed
    metadata (e.g. `contact_category`, `sales_channel`, `status`, `balance`,
    `total`, `taxes`, etc.). Sending these uncleaned triggers HTTP 400 validation
    errors like 'Invalid value passed for contact_category' or 'sales_channel'.
    """
    payload: dict[str, Any] = {
        "customer_id": raw.get("customer_id"),
        "invoice_number": raw.get("invoice_number"),
        "date": raw.get("date"),
        "due_date": raw.get("due_date"),
    }

    # Optional header fields
    for field in (
        "reference_number",
        "salesperson_id",
        "notes",
        "terms",
        "discount",
        "discount_type",
        "is_discount_before_tax",
        "shipping_charge",
        "adjustment",
        "adjustment_description",
        "template_id",
        "payment_terms",
        "payment_terms_id",
    ):
        val = raw.get(field)
        if val is not None and val != "":
            payload[field] = val

    # Clean line items
    raw_lines = raw.get("line_items", [])
    cleaned_lines = []
    for line in raw_lines:
        line_item: dict[str, Any] = {
            "item_id": line.get("item_id"),
            "quantity": line.get("quantity"),
            "rate": line.get("rate"),
        }
        # Retain line_item_id so Zoho updates rather than re-creating line items
        if line.get("line_item_id"):
            line_item["line_item_id"] = line.get("line_item_id")

        if line.get("name"):
            line_item["name"] = line.get("name")
        if line.get("description"):
            line_item["description"] = line.get("description")
        if line.get("unit"):
            line_item["unit"] = line.get("unit")
        if line.get("unit_conversion_id"):
            line_item["unit_conversion_id"] = line.get("unit_conversion_id")
        if line.get("discount") is not None:
            line_item["discount"] = line.get("discount")
        if line.get("tax_id"):
            line_item["tax_id"] = line.get("tax_id")
        if line.get("location_id"):
            line_item["location_id"] = line.get("location_id")
        if line.get("account_id"):
            line_item["account_id"] = line.get("account_id")

        cleaned_lines.append(line_item)

    payload["line_items"] = cleaned_lines
    return payload


def send_invoice_back(client: ZohoClient, invoice_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Send invoice JSON back to Zoho Books using PUT /invoices/{invoice_id}."""
    logger.info(f"Sending JSON back to Zoho Books via PUT /invoices/{invoice_id} ...")
    resp = client.put(f"/invoices/{invoice_id}", json_data=payload)
    return resp


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch Zoho Books invoice and send it back via API.")
    parser.add_argument("--invoice-number", default="SMR-INV-00463", help="Invoice number to fetch (default: SMR-INV-00463)")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and prepare payload without sending PUT request")
    parser.add_argument("--send-raw", action="store_true", help="Send unmodified raw GET JSON to observe Zoho validation behavior")
    parser.add_argument("--save-dir", type=Path, default=Path(__file__).resolve().parent / "output", help="Directory to save payload files")

    args = parser.parse_args()
    client = ZohoClient()

    # Step 1: GET invoice from Zoho Books
    try:
        raw_invoice = get_invoice_by_number(client, args.invoice_number)
    except Exception as e:
        logger.error(f"Failed to retrieve invoice: {e}")
        return 1

    inv_id = str(raw_invoice["invoice_id"])
    logger.info(f"Successfully retrieved invoice {args.invoice_number} (ID: {inv_id})")

    # Save retrieved raw JSON
    args.save_dir.mkdir(parents=True, exist_ok=True)
    raw_file = args.save_dir / f"invoice_{args.invoice_number}_raw.json"
    raw_file.write_text(json.dumps(raw_invoice, indent=2), encoding="utf-8")
    logger.info(f"Saved raw invoice JSON to: {raw_file}")

    # Step 2: Prepare payload to send back
    if args.send_raw:
        logger.warning("--send-raw specified: using exact unmodified GET JSON for PUT.")
        payload_to_send = raw_invoice
    else:
        payload_to_send = prepare_invoice_update_payload(raw_invoice)

    prepared_file = args.save_dir / f"invoice_{args.invoice_number}_payload.json"
    prepared_file.write_text(json.dumps(payload_to_send, indent=2), encoding="utf-8")
    logger.info(f"Saved outgoing payload JSON to: {prepared_file}")

    if args.dry_run:
        logger.info("[Dry Run] Skipped PUT request. Prepared payload is ready.")
        print("\nPrepared Payload Preview:")
        print(json.dumps(payload_to_send, indent=2))
        return 0

    # Step 3: Send back to Zoho Books API
    try:
        response = send_invoice_back(client, inv_id, payload_to_send)
        logger.info(f"Zoho API Response Code: {response.get('code')}")
        logger.info(f"Zoho API Response Message: {response.get('message')}")
        print("\n--- Zoho Response ---")
        print(json.dumps(response, indent=2))
        return 0
    except Exception as e:
        logger.error(f"Failed sending invoice back to Zoho: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
