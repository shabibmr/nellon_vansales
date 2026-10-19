"""Fetch missing October 2026 invoices from Zoho Books API into output/cache/invoices/.

1. Identifies invoices in Zoho Books for 2026-10-01 to 2026-10-19 missing from zoho-koyson.sales_invoices.
2. Checks local output/oct_fetch for any already-fetched detail files.
3. Fetches the remaining detail files via GET /invoices/{invoice_id} with rate-limit handling.
4. Saves raw JSON files to output/cache/invoices/{invoice_id}.json.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

from zoho_client import ZohoClient

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / ".env.mis")

CACHE_DIR = BASE_DIR / "output" / "cache" / "invoices"
OCT_FETCH_DIR = Path("/home/nellon/nellon_vansales/reports/mis/output/oct_fetch")


def connect(db: str = "zoho-koyson") -> pymysql.Connection:
    return pymysql.connect(
        host=os.getenv("MIS_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("MIS_DB_PORT", "3306")),
        user=os.getenv("MIS_DB_USER", "user2grey"),
        password=os.getenv("MIS_DB_PASSWORD", "user2grey"),
        database=db,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def get_existing_db_invoice_ids(conn: pymysql.Connection, start_date: str = "2026-10-01") -> set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT invoice_id FROM sales_invoices WHERE date >= %s", (start_date,))
        return {r["invoice_id"] for r in cur.fetchall()}


def list_zoho_invoices(client: ZohoClient, start_date: str, end_date: str) -> list[dict[str, Any]]:
    page = 1
    invoices = []
    while True:
        res = client.get("/invoices", params={
            "date_start": start_date,
            "date_end": end_date,
            "page": page,
            "per_page": 200,
            "sort_column": "date"
        })
        invs = res.get("invoices", [])
        invoices.extend(invs)
        context = res.get("page_context", {})
        if not context.get("has_more_page"):
            break
        page += 1
    return invoices


def fetch_invoice_with_retry(client: ZohoClient, invoice_id: str, max_retries: int = 5) -> dict[str, Any]:
    for attempt in range(1, max_retries + 1):
        try:
            return client.get(f"/invoices/{invoice_id}", params={"accept": "json"})
        except Exception as e:
            msg = str(e)
            if "429" in msg or "Too Many Requests" in msg:
                wait_time = 2.0 * attempt
                print(f"  [Rate Limit 429] Waiting {wait_time}s before retry {attempt}/{max_retries}...")
                time.sleep(wait_time)
            elif attempt < max_retries:
                time.sleep(1.0)
            else:
                raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--from", dest="dfrom", default="2026-10-01", help="Start date (default: 2026-10-01)")
    parser.add_argument("--to", dest="dto", default="2026-10-19", help="End date (default: 2026-10-19)")
    parser.add_argument("--pause", type=float, default=0.15, help="Pause between API calls (default: 0.15s)")
    args = parser.parse_args()

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Connecting to zoho-koyson to check existing invoices >= {args.dfrom}...")
    conn = connect("zoho-koyson")
    try:
        existing_ids = get_existing_db_invoice_ids(conn, args.dfrom)
    finally:
        conn.close()
    print(f"Existing invoices in zoho-koyson: {len(existing_ids)}")

    print(f"Listing Zoho Books invoices from {args.dfrom} to {args.dto}...")
    client = ZohoClient()
    zoho_invoices = list_zoho_invoices(client, args.dfrom, args.dto)
    print(f"Total Zoho Books invoices in date range: {len(zoho_invoices)}")

    zoho_by_id = {inv["invoice_id"]: inv for inv in zoho_invoices}
    missing_ids = [iid for iid in zoho_by_id if iid not in existing_ids]
    print(f"Missing invoices in zoho-koyson: {len(missing_ids)}")

    if not missing_ids:
        print("No missing invoices found. Done.")
        return 0

    from collections import Counter
    by_date = Counter(zoho_by_id[iid]["date"] for iid in missing_ids)
    print("\nMissing invoices by date:")
    for d in sorted(by_date):
        print(f"  {d}: {by_date[d]}")

    copied_count = 0
    fetched_count = 0
    cached_count = 0

    print("\nFetching invoice detail files...")
    for idx, iid in enumerate(missing_ids, 1):
        target_path = CACHE_DIR / f"{iid}.json"
        
        # 1. If already in local cache, keep it
        if target_path.exists():
            cached_count += 1
            continue

        # 2. Check if in OCT_FETCH_DIR
        oct_source = OCT_FETCH_DIR / f"{iid}.json"
        if oct_source.exists():
            shutil.copy(oct_source, target_path)
            copied_count += 1
            continue

        # 3. Fetch from Zoho Books API
        body = fetch_invoice_with_retry(client, iid)
        # Standardize cache structure: body usually has {"code": 0, "message": "success", "invoice": {...}}
        # If wrapped under "invoice", write it or the full body
        target_path.write_text(json.dumps(body, ensure_ascii=False), encoding="utf-8")
        fetched_count += 1
        time.sleep(args.pause)

        if idx % 20 == 0 or idx == len(missing_ids):
            print(f"  Progress: {idx}/{len(missing_ids)} (copied: {copied_count}, fetched: {fetched_count}, already cached: {cached_count})")

    print(f"\nAll {len(missing_ids)} missing invoices are now in {CACHE_DIR}:")
    print(f"  Copied from oct_fetch: {copied_count}")
    print(f"  Fetched from API:      {fetched_count}")
    print(f"  Already in cache:      {cached_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
