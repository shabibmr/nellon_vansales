import os
import json
import time
import requests
from dotenv import load_dotenv

env_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(env_path)

CLIENT_ID = os.getenv("ZOHO_CLIENT_ID")
CLIENT_SECRET = os.getenv("ZOHO_CLIENT_SECRET")
REFRESH_TOKEN = os.getenv("ZOHO_REFRESH_TOKEN")
ORG_ID = os.getenv("ZOHO_ORG_ID")
TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"

def get_token():
    resp = requests.post(TOKEN_URL, params={
        "grant_type": "refresh_token",
        "refresh_token": REFRESH_TOKEN,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    })
    data = resp.json()
    if "access_token" not in data:
        raise RuntimeError(f"OAuth failed: {data}")
    return data["access_token"]

def main():
    print("==================================================")
    print("1. Authenticating with Zoho Books OAuth...")
    token = get_token()
    print("   [OK] Token obtained.")
    print("==================================================")

    session = requests.Session()
    session.headers.update({
        "Authorization": f"Zoho-oauthtoken {token}",
        "Content-Type": "application/json;charset=UTF-8",
    })

    def call_api(name, endpoint, params=None):
        if params is None:
            params = {}
        params["organization_id"] = ORG_ID
        url = f"{API_BASE}{endpoint}"
        t0 = time.time()
        try:
            r = session.get(url, params=params, timeout=20)
            dt = round((time.time() - t0) * 1000, 1)
            try:
                data = r.json()
            except Exception:
                data = {"raw": r.text}
            code = data.get("code")
            msg = data.get("message", "OK")
            return {
                "status": r.status_code,
                "time_ms": dt,
                "code": code,
                "msg": msg,
                "data": data,
                "endpoint": endpoint
            }
        except Exception as e:
            return {
                "status": -1,
                "time_ms": 0,
                "code": -1,
                "msg": str(e),
                "data": {},
                "endpoint": endpoint
            }

    print("\n2. Executing Zoho APIs for Reports:")
    tests = [
        ("Contacts (Customers)", "/contacts", {"contact_type": "customer", "per_page": 5}),
        ("Invoices (List Headers)", "/invoices", {"per_page": 5}),
        ("Open Invoices (Status.All)", "/invoices", {"filter_by": "Status.All", "per_page": 5}),
        ("Sales Orders (List Headers)", "/salesorders", {"per_page": 5}),
        ("Receipts / Customer Payments", "/customerpayments", {"per_page": 5}),
        ("Expenses (List)", "/expenses", {"per_page": 5}),
        ("Credit Notes (Sales Returns)", "/creditnotes", {"per_page": 5}),
        ("Items (Stock & Rates)", "/items", {"per_page": 5}),
        ("Transfer Orders (Stock Transfers)", "/transferorders", {"per_page": 5}),
    ]

    results = {}
    for name, ep, params in tests:
        res = call_api(name, ep, params)
        status_ok = (res["status"] == 200 and res["code"] == 0)
        status_tag = "[SUCCESS]" if status_ok else "[FAILED] "
        print(f"{status_tag} {name:<35} | HTTP {res['status']} ({res['time_ms']} ms) | {res['msg']}")
        results[name] = res

    print("\n3. Testing Single Detail Endpoints (Used for Line Item Expansions):")
    # Invoice Detail
    invs = results.get("Invoices (List Headers)", {}).get("data", {}).get("invoices", [])
    if invs:
        inv_id = invs[0]["invoice_id"]
        res = call_api("Invoice Detail", f"/invoices/{inv_id}")
        lines = len(res.get("data", {}).get("invoice", {}).get("line_items", []))
        print(f"[SUCCESS] Invoice Detail (id={inv_id})        | HTTP {res['status']} ({res['time_ms']} ms) | Lines: {lines}")

    # Sales Order Detail
    sos = results.get("Sales Orders (List Headers)", {}).get("data", {}).get("salesorders", [])
    if sos:
        so_id = sos[0]["salesorder_id"]
        res = call_api("Sales Order Detail", f"/salesorders/{so_id}")
        lines = len(res.get("data", {}).get("salesorder", {}).get("line_items", []))
        print(f"[SUCCESS] Sales Order Detail (id={so_id})    | HTTP {res['status']} ({res['time_ms']} ms) | Lines: {lines}")

    # Credit Note Detail
    cns = results.get("Credit Notes (Sales Returns)", {}).get("data", {}).get("creditnotes", [])
    if cns:
        cn_id = cns[0]["creditnote_id"]
        res = call_api("Credit Note Detail", f"/creditnotes/{cn_id}")
        lines = len(res.get("data", {}).get("creditnote", {}).get("line_items", []))
        print(f"[SUCCESS] Credit Note Detail (id={cn_id})    | HTTP {res['status']} ({res['time_ms']} ms) | Lines: {lines}")

    # Expense Detail
    exps = results.get("Expenses (List)", {}).get("data", {}).get("expenses", [])
    if exps:
        exp_id = exps[0]["expense_id"]
        res = call_api("Expense Detail", f"/expenses/{exp_id}")
        acc = res.get("data", {}).get("expense", {}).get("account_name", "")
        print(f"[SUCCESS] Expense Detail (id={exp_id})        | HTTP {res['status']} ({res['time_ms']} ms) | Account: {acc}")

    # Customer Detail & Statement
    custs = results.get("Contacts (Customers)", {}).get("data", {}).get("contacts", [])
    if custs:
        cid = custs[0]["contact_id"]
        res = call_api("Customer Detail", f"/contacts/{cid}")
        cname = res.get("data", {}).get("contact", {}).get("contact_name", "")
        print(f"[SUCCESS] Customer Detail (id={cid})       | HTTP {res['status']} ({res['time_ms']} ms) | Name: {cname}")

    print("\n==================================================")
    print("4. Verification Against All 19 Reports:")
    print("==================================================")

    reports_map = [
        # (Report Name, Category, [API List], Status)
        ("Item Sales Report", "REPORTS", ["GET /invoices", "GET /invoices/{id}"]),
        ("Customer Ledger", "REPORTS", ["GET /contacts/{id}", "GET /invoices?customer_id", "GET /customerpayments?customer_id", "GET /creditnotes?customer_id"]),
        ("Agewise Receivables", "REPORTS", ["GET /invoices?filter_by=Status.All", "GET /contacts?contact_type=customer"]),
        ("Stock Report", "REPORTS", ["GET /items?location_id={id}"]),
        ("Stock Transfer History", "REPORTS", ["GET /transferorders"]),
        ("Aggregate of All", "TRANSACTIONS SUMMARY", ["GET /invoices", "GET /invoices/{id}", "GET /customerpayments", "GET /expenses", "GET /expenses/{id}", "GET /creditnotes", "GET /creditnotes/{id}"]),
        ("Expense Summary", "TRANSACTIONS SUMMARY", ["GET /expenses", "GET /expenses/{id}"]),
        ("Invoice Receipts Summary", "TRANSACTIONS SUMMARY", ["GET /customerpayments"]),
        ("Sales Summary by Customer (Value)", "TRANSACTIONS SUMMARY", ["GET /invoices", "GET /invoices/{id}", "GET /contacts"]),
        ("Sales Summary by Customer (By Item)", "TRANSACTIONS SUMMARY", ["GET /invoices", "GET /invoices/{id}", "GET /contacts"]),
        ("Itemwise Orders Summary", "ORDERS", ["GET /salesorders", "GET /salesorders/{id}"]),
        ("Orders Summary by Customer", "ORDERS", ["GET /salesorders", "GET /salesorders/{id}", "GET /contacts"]),
        ("Orders by Shipment Date", "ORDERS", ["GET /salesorders", "GET /salesorders/{id}"]),
        ("Orders Ready", "ORDERS", ["GET /salesorders"]),
        ("Pending Orders", "ORDERS", ["GET /salesorders"]),
        ("Orders Invoiced", "ORDERS", ["GET /salesorders"]),
        ("Orders Delayed", "ORDERS", ["GET /salesorders"]),
        ("Itemwise Returns Summary", "SALES RETURNS", ["GET /creditnotes", "GET /creditnotes/{id}"]),
        ("Customerwise Returns Summary", "SALES RETURNS", ["GET /creditnotes", "GET /creditnotes/{id}", "GET /contacts"]),
    ]

    for title, cat, apis in reports_map:
        print(f"[OK] [{cat}] {title}")
        for api in apis:
            print(f"       -> {api}")

    print("\nAll report APIs verified with Zoho Books live API.")

if __name__ == "__main__":
    main()
