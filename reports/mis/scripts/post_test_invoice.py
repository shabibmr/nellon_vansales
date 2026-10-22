#!/usr/bin/env python3
"""Post test_invoice_TEST-INV-1111.json to Zoho Books and mark it Sent.

POST /invoices?ignore_auto_number_generation=true, then
POST /invoices/{id}/status/sent (marks sent without emailing the customer).

Usage:
    .venv/bin/python -m scripts.post_test_invoice --dry-run   # print payload only
    .venv/bin/python -m scripts.post_test_invoice
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from common.zoho_client import ZohoClient

PAYLOAD = Path(__file__).resolve().parent.parent / "data" / "test_invoice_TEST-INV-1111.json"
if not PAYLOAD.exists():
    PAYLOAD = Path(__file__).resolve().parent.parent / "test_invoice_TEST-INV-1111.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    payload = json.loads(PAYLOAD.read_text())
    payload["date"] = date.today().isoformat()  # today only; due_date left as in the JSON
    if args.dry_run:
        print(json.dumps(payload, indent=2))
        return 0

    client = ZohoClient()
    resp = client.post("/invoices", json_data=payload, params={"ignore_auto_number_generation": "true"})
    inv = resp.get("invoice", {})
    inv_id = inv.get("invoice_id")
    print(f"Created {inv.get('invoice_number')} (id {inv_id}) status={inv.get('status')}")

    sent = client.post(f"/invoices/{inv_id}/status/sent")
    print(f"Mark sent: {sent.get('code')} {sent.get('message')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
