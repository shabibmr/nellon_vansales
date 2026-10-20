"""Fetch general ledger account postings from Zoho Books and seed zoho-koyson.gl_journals.

Endpoint:
    GET /chartofaccounts/transactions?account_id={account_id}&per_page=200&page={page}&date.start={from}&date.end={to}

Avoids individual voucher calls by querying postings at the account level in batches of 200.
Pre-filtered against active accounts identified in the pre-flight GL report.

Usage:
    # Dry-run: simulate fetching/planning without writing to DB
    python fetch_and_seed_gl_journals.py --dry-run

    # Apply: fetch from Zoho and upsert into gl_journals
    python fetch_and_seed_gl_journals.py --apply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

from reports.account_postings import COLUMNS, to_row as postings_to_row
from seed_common import upsert_sql
from zoho_client import ZohoClient

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / ".env.mis")

PREFLIGHT_FILE = BASE_DIR / "output" / "preflight_generalledger_2026-04-01_2026-10-19.json"
DEFAULT_FROM = "2026-04-01"
DEFAULT_TO = "2026-10-19"
COST_OF_SALES_ID = "3331482000000034003"
PER_PAGE = 200

UPSERT_SQL = upsert_sql("gl_journals", COLUMNS, {"account_id", "categorized_transaction_id"})


def connect() -> pymysql.Connection:
    return pymysql.connect(
        host=os.getenv("MIS_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("MIS_DB_PORT", "3306")),
        user=os.getenv("MIS_DB_USER", "user2grey"),
        password=os.getenv("MIS_DB_PASSWORD", "user2grey"),
        database=os.getenv("MIS_DB_NAME", "zoho-koyson"),
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def load_preflight_accounts(include_cos: bool = False) -> list[dict[str, Any]]:
    if not PREFLIGHT_FILE.exists():
        raise SystemExit(f"Pre-flight file {PREFLIGHT_FILE} not found. Run pre-flight check first.")

    with open(PREFLIGHT_FILE, encoding="utf-8") as f:
        data = json.load(f)

    gl = data.get("generalledger") or []
    conn = connect()
    with conn.cursor() as cur:
        cur.execute("SELECT account_id, account_code, account_name, group_ledger FROM accounts")
        db_accounts = {r["account_id"]: r for r in cur.fetchall()}
    conn.close()

    targets = []
    for acc in gl:
        aid = str(acc.get("account_id") or "")
        dr = float(acc.get("debit_total") or 0.0)
        cr = float(acc.get("credit_total") or 0.0)
        bal = float(acc.get("balance") or 0.0)

        # Skip zero activity
        if dr == 0.0 and cr == 0.0 and bal == 0.0:
            continue

        db_info = db_accounts.get(aid)
        if not db_info:
            print(f"Warning: Account {aid} ({acc.get('name')}) not found in DB accounts table! Skipping.", file=sys.stderr)
            continue

        # Skip group accounts
        if db_info.get("group_ledger") == "Group":
            continue

        # Skip Cost of Sales unless explicitly requested
        if aid == COST_OF_SALES_ID and not include_cos:
            continue

        targets.append({
            "account_id": aid,
            "account_code": db_info.get("account_code") or acc.get("account_code") or "",
            "account_name": db_info.get("account_name") or acc.get("name") or "",
            "dr": dr,
            "cr": cr,
            "balance": bal,
        })

    return targets


def safe_get(client: ZohoClient, endpoint: str, params: dict[str, Any], max_retries: int = 5) -> dict:
    for attempt in range(max_retries):
        try:
            return client.get(endpoint, params=params)
        except Exception as e:
            err_str = str(e)
            if "429" in err_str or "rate" in err_str.lower() or "limit" in err_str.lower():
                wait = 15 * (attempt + 1)
                print(f"  [Rate limit / 429 hit] Sleeping {wait}s before retry...", file=sys.stderr, flush=True)
                time.sleep(wait)
            elif attempt < max_retries - 1:
                print(f"  [Transient error: {e}] Retrying in 2s...", file=sys.stderr, flush=True)
                time.sleep(2)
            else:
                raise
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from-date", default=DEFAULT_FROM, help=f"Start date (default: {DEFAULT_FROM})")
    parser.add_argument("--to-date", default=DEFAULT_TO, help=f"End date (default: {DEFAULT_TO})")
    parser.add_argument("--dry-run", action="store_true", help="Simulate without live write (default)")
    parser.add_argument("--apply", action="store_true", help="Write to DB (default: dry-run)")
    parser.add_argument("--include-cos", action="store_true", help="Include Cost of Sales account (already seeded)")
    parser.add_argument("--pause", type=float, default=0.85, help="Pause seconds between Zoho API calls (default 0.85)")
    parser.add_argument("--resume", action="store_true", help="Skip accounts that already have postings in DB for this date range")
    parser.add_argument("--max-calls", type=int, default=800, help="Safety stop for API call budget (default 800)")
    args = parser.parse_args()

    targets = load_preflight_accounts(include_cos=args.include_cos)

    # If resume is requested, filter out accounts already seeded in range
    already_seeded: set[str] = set()
    conn_chk = connect()
    with conn_chk.cursor() as cur:
        cur.execute(
            "SELECT DISTINCT account_id FROM gl_journals WHERE transaction_date BETWEEN %s AND %s",
            (args.from_date, args.to_date)
        )
        already_seeded = {r["account_id"] for r in cur.fetchall()}
    conn_chk.close()

    if args.resume and already_seeded:
        before_cnt = len(targets)
        targets = [t for t in targets if t["account_id"] not in already_seeded]
        print(f"Resume active: skipped {before_cnt - len(targets)} accounts already seeded in DB.")

    print(f"Loaded {len(targets)} active ledger accounts to seed for period {args.from_date} .. {args.to_date}")
    print(f"Mode: {'APPLY (Live write to database)' if args.apply else 'DRY-RUN (Simulated)'}")
    print(f"Call budget safety cap: {args.max_calls} calls, pause: {args.pause}s between calls\n", flush=True)

    if not args.apply:
        print("Dry run summary of accounts to be fetched:")
        for idx, t in enumerate(targets[:15], 1):
            print(f"  {idx:3d}. {t['account_code']:10} {t['account_name'][:35]:35} (Dr: {t['dr']:12,.2f}, Cr: {t['cr']:12,.2f})")
        if len(targets) > 15:
            print(f"  ... and {len(targets) - 15} more accounts.")
        print("\nRe-run with --apply to execute.")
        return 0

    client = ZohoClient()
    conn = connect()

    total_calls = 0
    total_rows_saved = 0
    start_time = time.time()

    try:
        with conn.cursor() as cur:
            for idx, target in enumerate(targets, 1):
                aid = target["account_id"]
                code = target["account_code"]
                name = target["account_name"]

                page = 1
                account_rows: list[dict[str, Any]] = []

                while True:
                    if total_calls >= args.max_calls:
                        raise RuntimeError(f"Reached safety cap of {args.max_calls} API calls. Stopping.")

                    total_calls += 1
                    if total_calls > 1 and args.pause > 0:
                        time.sleep(args.pause)

                    params = {
                        "account_id": aid,
                        "per_page": PER_PAGE,
                        "page": page,
                        "date_start": args.from_date,
                        "date_end": args.to_date,
                    }

                    resp = safe_get(client, "/chartofaccounts/transactions", params=params)
                    txns = resp.get("transactions") or []
                    ctx = resp.get("page_context") or {}

                    for t in txns:
                        payload = dict(t)
                        if not payload.get("account_id"):
                            payload["account_id"] = aid
                        if not ctx.get("account_name"):
                            ctx = {**ctx, "account_name": name, "account_code": code}
                        account_rows.append(postings_to_row(payload, ctx))

                    has_more = bool(ctx.get("has_more_page"))
                    if not has_more or len(txns) < PER_PAGE:
                        break
                    page += 1

                # Upsert into gl_journals
                if account_rows:
                    for i in range(0, len(account_rows), 1000):
                        cur.executemany(UPSERT_SQL, account_rows[i : i + 1000])
                    conn.commit()
                    total_rows_saved += len(account_rows)

                elapsed = time.time() - start_time
                print(
                    f"[{idx:3d}/{len(targets):3d}] {code:10} {name[:30]:30} -> "
                    f"{len(account_rows):5d} rows ({page} pages) | Total calls: {total_calls} | "
                    f"Elapsed: {elapsed:.1f}s",
                    flush=True
                )

    except Exception as exc:
        conn.rollback()
        print(f"\nExecution interrupted: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    total_time = time.time() - start_time
    print(f"\n Seeding Completed in {total_time:.1f}s!")
    print(f"Total API Calls Made: {total_calls}")
    print(f"Total Rows Saved / Upserted: {total_rows_saved:,}")

    # Reconcile against target DB
    conn = connect()
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) AS total_rows, COUNT(DISTINCT account_id) AS distinct_accounts FROM gl_journals")
        db_stat = cur.fetchone()
        print(f"Current DB gl_journals state: {db_stat['total_rows']:,} rows across {db_stat['distinct_accounts']} accounts")
    conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
