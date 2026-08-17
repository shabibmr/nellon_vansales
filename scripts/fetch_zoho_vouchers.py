#!/usr/bin/env python3
"""
Fetch Live Zoho Books Responses for 5 Vouchers
---------------------------------------------
1. Obtains a fresh OAuth access token.
2. Calls list endpoints for all 5 voucher types (+ Transfer Orders).
3. Dynamically resolves the most recent record ID for each voucher.
4. Calls detail endpoints to retrieve full line items & allocations.
5. Saves formatted JSON files to assets/data/zoho/.
"""

import json
import os
import sys
import time
import requests
from dotenv import load_dotenv

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(PROJECT_ROOT, "zoho_endpoints", ".env")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "assets", "data", "zoho")

load_dotenv(ENV_PATH)

def _require_env(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key} (in {ENV_PATH})")
    return val

CLIENT_ID     = _require_env("ZOHO_CLIENT_ID")
CLIENT_SECRET = _require_env("ZOHO_CLIENT_SECRET")
REFRESH_TOKEN = _require_env("ZOHO_REFRESH_TOKEN")
ORG_ID        = _require_env("ZOHO_ORG_ID")
TOKEN_URL     = "https://accounts.zoho.com/oauth/v2/token"
API_BASE      = "https://www.zohoapis.com/books/v3"

os.makedirs(OUTPUT_DIR, exist_ok=True)

def get_access_token() -> str:
    print("Obtaining fresh OAuth access token from Zoho...")
    resp = requests.post(
        TOKEN_URL,
        params={
            "grant_type": "refresh_token",
            "refresh_token": REFRESH_TOKEN,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        },
        timeout=30,
    )
    data = resp.json()
    if "access_token" not in data:
        raise RuntimeError(f"Token refresh failed: {data}")
    print(f"  [OK] Access token obtained (expires in {data.get('expires_in')}s)")
    return data["access_token"]

def save_json(filename: str, data: dict):
    filepath = os.path.join(OUTPUT_DIR, filename)
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    size_kb = round(os.path.getsize(filepath) / 1024, 2)
    print(f"  [SAVED] {filename:<28} ({size_kb} KB)")

def main():
    token = get_access_token()
    headers = {
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json",
        "JSONString": "true",
    }
    base_params = {
        "organization_id": ORG_ID,
        "per_page": 200,
        "page": 1,
    }

    # Configuration for the 5 vouchers + Transfer Orders
    vouchers = [
        {
            "name": "Sales Invoices",
            "list_path": "/invoices",
            "list_key": "invoices",
            "id_key": "invoice_id",
            "list_file": "invoices.json",
            "detail_file": "invoice_detail.json",
            "detail_envelope": "invoice",
        },
        {
            "name": "Sales Orders",
            "list_path": "/salesorders",
            "list_key": "salesorders",
            "id_key": "salesorder_id",
            "list_file": "sales_orders.json",
            "detail_file": "sales_order_detail.json",
            "detail_envelope": "salesorder",
        },
        {
            "name": "Customer Payments / Receipts",
            "list_path": "/customerpayments",
            "list_key": "customerpayments",
            "id_key": "payment_id",
            "list_file": "receipts.json",
            "detail_file": "receipt_detail.json",
            "detail_envelope": "payment",
        },
        {
            "name": "Credit Notes / Returns",
            "list_path": "/creditnotes",
            "list_key": "creditnotes",
            "id_key": "creditnote_id",
            "list_file": "credit_notes.json",
            "detail_file": "credit_note_detail.json",
            "detail_envelope": "creditnote",
        },
        {
            "name": "Expenses",
            "list_path": "/expenses",
            "list_key": "expenses",
            "id_key": "expense_id",
            "list_file": "expenses.json",
            "detail_file": "expense_detail.json",
            "detail_envelope": "expense",
        },
        {
            "name": "Transfer Orders (Stock Transfers)",
            "list_path": "/transferorders",
            "list_key": "transfer_orders",
            "id_key": "transfer_order_id",
            "list_file": "transfer_orders.json",
            "detail_file": "transfer_order_detail.json",
            "detail_envelope": "transfer_order",
        },
    ]

    print(f"\nFetching live JSON for {len(vouchers)} voucher types from Org {ORG_ID}...\n")

    for v in vouchers:
        print(f"=== {v['name']} ===")
        # 1. Fetch List
        list_url = f"{API_BASE}{v['list_path']}"
        resp = requests.get(list_url, headers=headers, params=base_params, timeout=30)
        if resp.status_code != 200:
            print(f"  [ERROR] List fetch failed: HTTP {resp.status_code} - {resp.text[:200]}")
            continue

        list_data = resp.json()
        save_json(v["list_file"], list_data)

        records = list_data.get(v["list_key"], [])
        if not records:
            # Fallback if alternate key format is returned
            for val in list_data.values():
                if isinstance(val, list) and val:
                    records = val
                    break

        print(f"  Records fetched: {len(records)}")

        # 2. Pick latest record ID for Detail
        if records:
            latest_record = records[-1]
            latest_id = str(latest_record.get(v["id_key"]) or latest_record.get("id") or "")
            if latest_id:
                print(f"  Latest ID resolved: {latest_id}")
                detail_url = f"{API_BASE}{v['list_path']}/{latest_id}"
                det_resp = requests.get(
                    detail_url,
                    headers=headers,
                    params={"organization_id": ORG_ID},
                    timeout=30,
                )
                if det_resp.status_code == 200:
                    det_data = det_resp.json()
                    save_json(v["detail_file"], det_data)
                else:
                    print(f"  [WARN] Detail fetch failed: HTTP {det_resp.status_code}")
            else:
                print(f"  [WARN] Could not find {v['id_key']} in latest record")
        else:
            print(f"  [INFO] No records found to fetch detail.")
        print()

    print("All voucher responses fetched and saved to assets/data/zoho/ successfully!")

if __name__ == "__main__":
    main()
