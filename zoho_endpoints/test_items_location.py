"""
Quick standalone check of GET /inventory/v1/items with a location_id filter,
using the same credential flow as the Flutter app (client_id/secret +
refresh_token -> access_token), so we can see the raw response/error.

Usage:
    python test_items_location.py [location_id]
"""

import os
import sys
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
API_BASE = "https://www.zohoapis.com/inventory/v1"

# Falls back to the SHINAD location id seen in zohodocs captures if none given.
DEFAULT_LOCATION_ID = "3331482000180671517"


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
    location_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LOCATION_ID

    token = get_access_token()

    headers = {
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json",
    }
    params = {
        "organization_id": ORG_ID,
        "location_id": location_id,
        "per_page": 200,
        "page": 1,
    }

    url = f"{API_BASE}/items"
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

    items = data.get("items", [])
    print(f"items returned: {len(items)}")
    page_context = data.get("page_context", {})
    print(f"page_context: {page_context}")

    if items:
        first = items[0]
        print("\nFirst record (key fields):")
        for k in (
            "item_id",
            "name",
            "stock_on_hand",
            "available_stock",
            "actual_available_stock",
            "location_id",
            "location_name",
            "location_stock_on_hand",
            "location_available_stock",
            "location_actual_available_stock",
        ):
            print(f"  {k}: {first.get(k)}")


if __name__ == "__main__":
    main()
