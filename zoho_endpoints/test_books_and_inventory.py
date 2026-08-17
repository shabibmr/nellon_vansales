"""
Zoho Books vs Zoho Inventory API Call Validator
------------------------------------------------
Demonstrates and validates exclusive API calls to Zoho Books (/books/v3)
and Zoho Inventory (/inventory/v1) using credentials from .env_zoho.
"""

import json
import os
import urllib.parse
import urllib.request


def load_env(env_path: str = ".env_zoho") -> dict:
    env = {}
    if not os.path.exists(env_path):
        env_path = os.path.join(os.path.dirname(__file__), "..", ".env_zoho")
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def get_oauth_token(client_id: str, client_secret: str, refresh_token: str) -> dict:
    print("1. Exchanging Refresh Token for Access Token...")
    params = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": client_id,
        "client_secret": client_secret,
    })
    req = urllib.request.Request(f"https://accounts.zoho.com/oauth/v2/token?{params}", method="POST")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())


def call_api(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())


def main():
    env = load_env()
    token_resp = get_oauth_token(
        env["ZOHO_CLIENT_ID"],
        env["ZOHO_CLIENT_SECRET"],
        env["ZOHO_REFRESH_TOKEN"],
    )
    access_token = token_resp["access_token"]
    org_id = env["ZOHO_ORG_ID"]
    raw_scopes = token_resp.get("scope", "")
    scopes_list = raw_scopes.split(" ")
    
    print(f"   [OK] Token obtained. Expires in: {token_resp.get('expires_in')}s")
    print(f"   [OK] Authorized Scopes ({len(scopes_list)}):")
    for s in scopes_list:
        print(f"        - {s}")

    # =========================================================================
    # 1. Zoho Books Exclusive: Chart of Accounts & Bank Accounts
    # =========================================================================
    print("\n" + "=" * 60)
    print("2. Calling ZOHO BOOKS Exclusive API (Chart of Accounts)")
    print("=" * 60)
    books_url = f"https://www.zohoapis.com/books/v3/chartofaccounts?organization_id={org_id}"
    print(f"   URL: {books_url}")
    books_res = call_api(books_url, access_token)
    accounts = books_res.get("chartofaccounts", [])
    print(f"   Status Code: {books_res.get('code')} ({books_res.get('message', 'success')})")
    print(f"   Total Accounts: {len(accounts)}")
    if accounts:
        print("   Sample Accounts:")
        for acc in accounts[:3]:
            print(f"     * [{acc.get('account_type')}] {acc.get('account_name')} (ID: {acc.get('account_id')})")

    # =========================================================================
    # 2. Zoho Inventory Exclusive: Warehouses & Transfer Orders
    # =========================================================================
    print("\n" + "=" * 60)
    print("3. Calling ZOHO INVENTORY Exclusive API (Warehouses)")
    print("=" * 60)
    inv_url = f"https://www.zohoapis.com/inventory/v1/warehouses?organization_id={org_id}"
    print(f"   URL: {inv_url}")
    inv_res = call_api(inv_url, access_token)
    warehouses = inv_res.get("warehouses", [])
    print(f"   Status Code: {inv_res.get('code')} ({inv_res.get('message', 'success')})")
    print(f"   Total Warehouses: {len(warehouses)}")
    if warehouses:
        print("   Sample Warehouses:")
        for wh in warehouses[:3]:
            print(f"     * {wh.get('warehouse_name')} (ID: {wh.get('warehouse_id')}, Primary: {wh.get('is_primary')}, Status: {wh.get('status')})")

    print("\n" + "=" * 60)
    print("4. Calling ZOHO INVENTORY Exclusive API (Transfer Orders)")
    print("=" * 60)
    to_url = f"https://www.zohoapis.com/inventory/v1/transferorders?organization_id={org_id}"
    print(f"   URL: {to_url}")
    to_res = call_api(to_url, access_token)
    transfer_orders = to_res.get("transfer_orders", [])
    print(f"   Status Code: {to_res.get('code')} ({to_res.get('message', 'success')})")
    print(f"   Total Transfer Orders (Page 1): {len(transfer_orders)}")
    if transfer_orders:
        print("   Sample Transfer Orders:")
        for t_order in transfer_orders[:3]:
            print(f"     * Order #: {t_order.get('transfer_order_number')} | From: {t_order.get('from_warehouse_name')} -> To: {t_order.get('to_warehouse_name')} | Status: {t_order.get('status')}")


if __name__ == "__main__":
    main()
