"""
Zoho Books API Endpoint Validator
----------------------------------
Reads endpoints.csv, obtains a fresh OAuth token, calls every GET endpoint,
and saves the raw JSON response to responses/<title>.json.

Usage:
    pip install requests
    python call_endpoints.py
"""

import csv
import json
import os
import time
import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

def _require_env(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key}  (set it in zoho_endpoints/.env)")
    return val

CLIENT_ID     = _require_env("ZOHO_CLIENT_ID")
CLIENT_SECRET = _require_env("ZOHO_CLIENT_SECRET")
REFRESH_TOKEN = _require_env("ZOHO_REFRESH_TOKEN")
ORG_ID        = _require_env("ZOHO_ORG_ID")
TOKEN_URL     = "https://accounts.zoho.com/oauth/v2/token"
API_BASE      = "https://www.zohoapis.com/books/v3"

RESPONSES_DIR = os.path.join(os.path.dirname(__file__), "responses")
ENDPOINTS_CSV = os.path.join(os.path.dirname(__file__), "endpoints.csv")

# Date range is fixed: 2026-04-01 -> today (auto-resolved at runtime)
DATE_START = "2026-04-01"

os.makedirs(RESPONSES_DIR, exist_ok=True)

# Placeholder → (response_file, list_key, id_field, selector)
# selector: "last" picks the final record; "max:<field>" picks the record with highest numeric field
PLACEHOLDER_SOURCES: dict[str, tuple[str, str, str, str]] = {
    "PLACEHOLDER_CUSTOMER_ID":        ("fetch_customers",                "contacts",          "contact_id",     "max:outstanding_receivable_amount"),
    "PLACEHOLDER_ITEM_ID":            ("fetch_items",                    "items",              "item_id",        "max:stock_on_hand"),
    "PLACEHOLDER_INVOICE_ID":         ("fetch_open_invoices",            "invoices",           "invoice_id",     "last"),
    "PLACEHOLDER_INVOICE_RECEIPT_ID": ("fetch_invoice_receipts_by_date", "customerpayments",   "payment_id",     "last"),
    "PLACEHOLDER_EXPENSE_ID":         ("fetch_expenses",                  "expenses",           "expense_id",    "last"),
    "PLACEHOLDER_PAYMENT_ID":         ("fetch_customer_payments",         "customerpayments",   "payment_id",    "last"),
    "PLACEHOLDER_CREDIT_NOTE_ID":     ("fetch_credit_notes",              "creditnotes",        "creditnote_id", "last"),
}


def _load_placeholder_ids() -> dict[str, str]:
    """Read stored response files and resolve all placeholder IDs."""
    resolved: dict[str, str] = {}
    for placeholder, (fname, list_key, id_field, selector) in PLACEHOLDER_SOURCES.items():
        path = os.path.join(RESPONSES_DIR, f"{fname}.json")
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        records = data.get(list_key, [])
        if not records:
            continue
        if selector == "last":
            record = records[-1]
        elif selector.startswith("max:"):
            field = selector[4:]
            record = max(records, key=lambda r: r.get(field) or 0)
        else:
            record = records[-1]
        resolved[placeholder] = str(record[id_field])
        print(f"  [ID]   {placeholder:<40} = {resolved[placeholder]}"
              f"  (from {fname}, selector={selector})")
    return resolved


def get_access_token() -> str:
    """Exchange the refresh token for a fresh access token."""
    print("Fetching OAuth access token …")
    resp = requests.post(TOKEN_URL, params={
        "grant_type":    "refresh_token",
        "refresh_token": REFRESH_TOKEN,
        "client_id":     CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    })
    data = resp.json()

    # Save the raw token response for inspection
    _save_json("oauth_token", data)

    if "access_token" not in data:
        raise RuntimeError(f"Token request failed: {data}")

    print(f"  [OK] access_token obtained (expires_in={data.get('expires_in')}s)\n")
    return data["access_token"]


def _save_json(title: str, payload: dict) -> str:
    path = os.path.join(RESPONSES_DIR, f"{title}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    return path


def _find_list_key(data: dict) -> str | None:
    """Return the first key whose value is a list (the records array)."""
    for k, v in data.items():
        if isinstance(v, list):
            return k
    return None


def call_endpoint(title: str, path: str, extra_params: str, token: str) -> dict:
    """Call a GET endpoint with full pagination (200 records/page) and save all records."""
    url = f"{API_BASE}{path}"

    base_params: dict = {"organization_id": ORG_ID, "per_page": 200, "page": 1}
    if extra_params:
        for pair in extra_params.split("&"):
            if "=" in pair:
                k, v = pair.split("=", 1)
                base_params[k] = v

    headers = {
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json",
    }

    all_records = []
    list_key = None
    last_data = {}
    start = time.time()

    try:
        resp = requests.get(url, headers=headers, params=base_params, timeout=30)
        data = resp.json()

        if resp.status_code != 200:
            elapsed = round(time.time() - start, 2)
            _save_json(title, data)
            print(f"  [FAIL] {title:<35} -> HTTP {resp.status_code}  ({elapsed}s)  {data.get('message', '')}")
            return {
                "title": title, "url": resp.url,
                "http_status": resp.status_code, "elapsed_s": elapsed,
                "zoho_code": data.get("code"), "zoho_msg": data.get("message", ""),
                "ok": False,
            }

        list_key = _find_list_key(data)
        all_records = data.get(list_key, []) if list_key else []
        last_data = data

        elapsed = round(time.time() - start, 2)

        merged = {k: v for k, v in last_data.items() if not isinstance(v, list)}
        if list_key:
            merged[list_key] = all_records
        merged["_pagination"] = {"total_records": len(all_records), "pages_fetched": 1}
        _save_json(title, merged)

        print(f"  [OK]   {title:<35} -> {len(all_records)} records  ({elapsed}s)")
        return {
            "title":         title,
            "url":           url,
            "http_status":   200,
            "elapsed_s":     elapsed,
            "pages_fetched": 1,
            "total_records": len(all_records),
            "ok":            True,
        }

    except Exception as exc:
        elapsed = round(time.time() - start, 2)
        print(f"  [ERR]  {title:<35} -> {exc}")
        _save_json(title, {"error": str(exc)})
        return {
            "title": title, "url": url,
            "elapsed_s": elapsed, "error": str(exc), "ok": False,
        }


def resolve_placeholders(text: str, ids: dict[str, str]) -> str | None:
    """Replace placeholder tokens in path or extra_params with resolved values.
    Returns None if a required placeholder has no resolved value (endpoint will be skipped)."""
    today = time.strftime("%Y-%m-%d")
    text = text.replace("CURRENT_DATE", today)
    for token in PLACEHOLDER_SOURCES:
        if token in text:
            value = ids.get(token, "")
            if not value:
                return None
            text = text.replace(token, value)
    return text


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--customer-id", default="", help="Zoho customer_id for filtered invoice lookups (auto-resolved if omitted)")
    parser.add_argument("--item-id",     default="", help="Zoho item_id for filtered invoice lookups (auto-resolved if omitted)")
    args = parser.parse_args()

    today = time.strftime("%Y-%m-%d")
    print(f"Date filter: {DATE_START} to {today}\n")

    token = get_access_token()

    # Seed CLI overrides into the ids dict (empty string = auto-resolve from file)
    ids: dict[str, str] = {}
    if args.customer_id:
        ids["PLACEHOLDER_CUSTOMER_ID"] = args.customer_id
    if args.item_id:
        ids["PLACEHOLDER_ITEM_ID"] = args.item_id

    results = []
    with open(ENDPOINTS_CSV, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["method"].upper() != "GET":
                continue

            # Refresh resolved IDs from any responses saved so far this run
            ids.update({k: v for k, v in _load_placeholder_ids().items() if k not in ids})

            path         = resolve_placeholders(row["path"],              ids)
            extra_params = resolve_placeholders(row["extra_params"].strip(), ids)

            if path is None or extra_params is None:
                missing = "path ID" if path is None else "extra_params ID"
                print(f"  [SKIP] {row['title']:<30} -> no {missing} resolved yet")
                results.append({"title": row["title"], "ok": None, "skipped": True})
                continue

            result = call_endpoint(
                title=row["title"],
                path=path,
                extra_params=extra_params,
                token=token,
            )
            results.append(result)

    # Write summary
    summary_path = _save_json("summary", {
        "run_at":        time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "date_filter":   f"{DATE_START} -> {time.strftime('%Y-%m-%d')}",
        "total":         len(results),
        "passed":        sum(1 for r in results if r.get("ok")),
        "failed":        sum(1 for r in results if r.get("ok") is False),
        "skipped":       sum(1 for r in results if r.get("skipped")),
        "total_records": sum(r.get("total_records", 0) for r in results),
        "endpoints":     results,
    })

    called   = [r for r in results if r.get("skipped") is not True]
    skipped  = [r for r in results if r.get("skipped")]
    print(f"\n{'-'*60}")
    print(f"Done. {sum(1 for r in called if r.get('ok'))}/{len(called)} endpoints OK."
          + (f"  {len(skipped)} skipped (no sample ID)." if skipped else ""))
    print(f"Summary: {summary_path}")
    print(f"Responses saved to: {RESPONSES_DIR}")


if __name__ == "__main__":
    main()
