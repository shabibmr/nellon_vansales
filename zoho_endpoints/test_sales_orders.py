"""
Quick standalone check of GET /salesorders against Zoho Books, using the
same credential flow as the Flutter app (client_id/secret + refresh_token
-> access_token), so we can see the raw response/error without the app's
error-message truncation in the way.

Usage:
    python test_sales_orders.py
"""

import os
import time
import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env_zoho"))


def _require_env(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key} (set it in .env_zoho)")
    return val


CLIENT_ID = _require_env("ZOHO_CLIENT_ID")
CLIENT_SECRET = _require_env("ZOHO_CLIENT_SECRET")
REFRESH_TOKEN = _require_env("ZOHO_REFRESH_TOKEN")
ORG_ID = _require_env("ZOHO_ORG_ID")

TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"


def get_access_token() -> str:
    print("Requesting OAuth access token ...")
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
        raise RuntimeError(f"Token refresh failed: HTTP {resp.status_code}: {data}")
    print(f"  OK - token obtained (expires_in={data.get('expires_in')}s)\n")
    return data["access_token"]


def main():
    token = get_access_token()

    headers = {
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json",
    }
    params = {
        "organization_id": ORG_ID,
        "per_page": 200,
        "page": 1,
    }

    url = f"{API_BASE}/salesorders"
    print(f"GET {url}")
    print(f"  params: {params}\n")

    start = time.time()
    try:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
    except requests.exceptions.RequestException as exc:
        print(f"REQUEST FAILED (network-level): {type(exc).__name__}: {exc}")
        return

    elapsed = round(time.time() - start, 2)
    print(f"HTTP {resp.status_code}  ({elapsed}s)")

    try:
        data = resp.json()
    except ValueError:
        print("Response was not valid JSON:")
        print(resp.text[:1000])
        return

    if resp.status_code != 200:
        print(f"Zoho error code: {data.get('code')}")
        print(f"Zoho message:    {data.get('message')}")
        print("\nFull body:")
        print(data)
        return

    orders = data.get("salesorders", [])
    print(f"salesorders returned: {len(orders)}")
    page_context = data.get("page_context", {})
    print(f"page_context: {page_context}")

    if orders:
        first = orders[0]
        print("\nFirst record (key fields):")
        for k in ("salesorder_id", "salesorder_number", "customer_name", "date", "status", "salesperson_id", "salesperson_name", "location_id"):
            print(f"  {k}: {first.get(k)}")


if __name__ == "__main__":
    main()
