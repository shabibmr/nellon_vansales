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

# -- Credentials (from zoho_api_client.dart) ----------------------------------
CLIENT_ID     = "1000.45EI6FPO004OW9W6BTB7TUJ9L0C0YP"
CLIENT_SECRET = "1d829f7ee3e1eb7debe6ed370ccc87ab45e7b36103"
REFRESH_TOKEN = "1000.ccb7c895a473ba5569c55565c0aed87d.c2f3a5530356193d39a19c511efed856"
ORG_ID        = "783019958"
TOKEN_URL     = "https://accounts.zoho.com/oauth/v2/token"
API_BASE      = "https://www.zohoapis.com/books/v3"

RESPONSES_DIR = os.path.join(os.path.dirname(__file__), "responses")
ENDPOINTS_CSV = os.path.join(os.path.dirname(__file__), "endpoints.csv")

# Override placeholder IDs here before running, or pass via CLI:
#   python call_endpoints.py --customer-id 123456789 --item-id 987654321
SAMPLE_CUSTOMER_ID = ""
SAMPLE_ITEM_ID     = ""

# Date range is fixed: 2026-04-01 -> today (auto-resolved at runtime)
DATE_START = "2026-04-01"

os.makedirs(RESPONSES_DIR, exist_ok=True)


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

    base_params: dict = {"organization_id": ORG_ID, "per_page": 200}
    if extra_params:
        for pair in extra_params.split("&"):
            if "=" in pair:
                k, v = pair.split("=", 1)
                base_params[k] = v  # per_page from CSV overrides default if present

    headers = {
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json",
    }

    all_records = []
    list_key = None
    page = 1
    last_data = {}
    start = time.time()

    try:
        while True:
            params = {**base_params, "page": page}
            resp = requests.get(url, headers=headers, params=params, timeout=30)
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

            # Detect the records key on first page
            if list_key is None:
                list_key = _find_list_key(data)

            page_records = data.get(list_key, []) if list_key else []
            all_records.extend(page_records)
            last_data = data

            has_more = data.get("page_context", {}).get("has_more_page", False)
            print(f"    page {page}: {len(page_records)} records  (total so far: {len(all_records)})", end="\r")

            if not has_more:
                break
            page += 1

        elapsed = round(time.time() - start, 2)

        # Build merged response: keep metadata from last page, replace records list with full set
        merged = {k: v for k, v in last_data.items() if not isinstance(v, list)}
        if list_key:
            merged[list_key] = all_records
        merged["_pagination"] = {"total_records": len(all_records), "pages_fetched": page}
        _save_json(title, merged)

        print(f"  [OK]   {title:<35} -> {len(all_records)} records  ({page} page{'s' if page > 1 else ''}, {elapsed}s)")
        return {
            "title":         title,
            "url":           url,
            "http_status":   200,
            "elapsed_s":     elapsed,
            "pages_fetched": page,
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


def resolve_placeholders(extra_params: str) -> str | None:
    """Replace placeholder tokens with runtime values.
    Returns None if a required placeholder has no value set (endpoint will be skipped)."""
    today = time.strftime("%Y-%m-%d")
    replacements = {
        "PLACEHOLDER_CUSTOMER_ID": SAMPLE_CUSTOMER_ID,
        "PLACEHOLDER_ITEM_ID":     SAMPLE_ITEM_ID,
        "CURRENT_DATE":            today,
    }
    for token, value in replacements.items():
        if token in extra_params:
            if not value:
                return None
            extra_params = extra_params.replace(token, value)
    return extra_params


def main():
    global SAMPLE_CUSTOMER_ID, SAMPLE_ITEM_ID
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--customer-id", default=SAMPLE_CUSTOMER_ID, help="Zoho customer_id for filtered invoice lookups")
    parser.add_argument("--item-id",     default=SAMPLE_ITEM_ID,     help="Zoho item_id for filtered invoice lookups")
    args = parser.parse_args()

    SAMPLE_CUSTOMER_ID = args.customer_id
    SAMPLE_ITEM_ID     = args.item_id

    today = time.strftime("%Y-%m-%d")
    print(f"Date filter: {DATE_START} to {today}\n")

    token = get_access_token()

    results = []
    with open(ENDPOINTS_CSV, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["method"].upper() != "GET":
                continue  # skip POST endpoints to avoid creating test records

            extra_params = resolve_placeholders(row["extra_params"].strip())
            if extra_params is None:
                print(f"  [SKIP] {row['title']:<30} -> no sample ID set (use --customer-id / --item-id)")
                results.append({"title": row["title"], "ok": None, "skipped": True})
                continue

            result = call_endpoint(
                title=row["title"],
                path=row["path"],
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
