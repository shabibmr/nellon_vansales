"""
Export Manual Journals Touching an Account
-------------------------------------------
Finds a chart-of-accounts entry by code/name (default "7.2." / "Depreciation Account"),
lists every transaction posted to it, keeps the manual-journal ones, fetches each journal's
full detail, and writes a CSV with one row per journal line item on that account.

Read-only — does not change anything in Zoho.

Usage:
    pip install requests python-dotenv
    python export_journals_by_account.py --list-only                 # just resolve the account(s)
    python export_journals_by_account.py --date-start 2025-04-01 --date-end 2026-03-31
    python export_journals_by_account.py --match "7.2." --match "Depreciation Account"
"""

import argparse
import csv
import os
import time
import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env_zoho"))


def _require_env(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key}  (set it in .env_zoho)")
    return val


CLIENT_ID = _require_env("ZOHO_CLIENT_ID")
CLIENT_SECRET = _require_env("ZOHO_CLIENT_SECRET")
REFRESH_TOKEN = _require_env("ZOHO_REFRESH_TOKEN")
ORG_ID = _require_env("ZOHO_ORG_ID")
TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"

OUT_DIR = os.path.join(os.path.dirname(__file__), "journal_exports")


def get_access_token() -> str:
    resp = requests.post(TOKEN_URL, params={
        "grant_type": "refresh_token",
        "refresh_token": REFRESH_TOKEN,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    })
    data = resp.json()
    if "access_token" not in data:
        raise RuntimeError(f"Token request failed: {data}")
    return data["access_token"]


def api_get(token: str, path: str, params: dict | None = None) -> dict:
    p = {"organization_id": ORG_ID, **(params or {})}
    resp = requests.get(f"{API_BASE}{path}", params=p,
                        headers={"Authorization": f"Zoho-oauthtoken {token}"})
    if resp.status_code == 429:
        time.sleep(10)
        return api_get(token, path, params)
    data = resp.json()
    if data.get("code") != 0:
        raise RuntimeError(f"{path} failed: {data}")
    return data


def paginate(token: str, path: str, list_key: str, params: dict | None = None) -> list[dict]:
    rows: list[dict] = []
    page = 1
    while True:
        data = api_get(token, path, {**(params or {}), "page": page, "per_page": 200})
        rows.extend(data.get(list_key, []))
        if not data.get("page_context", {}).get("has_more_page"):
            return rows
        page += 1


def find_accounts(token: str, needles: list[str]) -> list[dict]:
    accounts = paginate(token, "/chartofaccounts", "chartofaccounts")
    needles = [n.lower() for n in needles]
    return [
        a for a in accounts
        if any(n in f"{a.get('account_code', '')} {a.get('account_name', '')}".lower() for n in needles)
    ]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--match", action="append", default=None,
                    help="substring of account code/name (repeatable, any match). Default: 7.2. / Depreciation Account")
    ap.add_argument("--date-start")
    ap.add_argument("--date-end")
    ap.add_argument("--list-only", action="store_true", help="only resolve and print matching accounts")
    args = ap.parse_args()
    needles = args.match or ["7.2.", "Depreciation Account"]

    token = get_access_token()
    accounts = find_accounts(token, needles)
    print(f"{len(accounts)} matching account(s):")
    for a in accounts:
        print(f"  {a['account_id']}  code={a.get('account_code', '')!r}  name={a['account_name']!r}  type={a.get('account_type')}")
    if args.list_only or not accounts:
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    journal_ids: dict[str, dict] = {}
    for a in accounts:
        params = {"account_id": a["account_id"]}
        if args.date_start:
            params["date_start"] = args.date_start
        if args.date_end:
            params["date_end"] = args.date_end
        txns = paginate(token, "/chartofaccounts/transactions", "transactions", params)
        journals = [t for t in txns if "journal" in str(t.get("transaction_type", "")).lower()]
        print(f"  {a['account_name']}: {len(txns)} transactions, {len(journals)} journal-type")
        for t in journals:
            journal_ids[t["entity_id"]] = t

    target_ids = {a["account_id"] for a in accounts}
    out_path = os.path.join(OUT_DIR, f"journals_{time.strftime('%Y%m%d_%H%M%S')}.csv")
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["journal_id", "entry_number", "journal_date", "reference_number", "notes",
                    "journal_type", "account_code", "account_name", "debit_or_credit", "amount",
                    "line_description"])
        for jid in journal_ids:
            j = api_get(token, f"/journals/{jid}")["journal"]
            for li in j.get("line_items", []):
                if li.get("account_id") not in target_ids:
                    continue
                acct = next(a for a in accounts if a["account_id"] == li["account_id"])
                w.writerow([jid, j.get("entry_number"), j.get("journal_date"), j.get("reference_number"),
                            j.get("notes"), j.get("journal_type"), acct.get("account_code", ""),
                            li.get("account_name"), li.get("debit_or_credit"), li.get("amount"),
                            li.get("description")])
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
