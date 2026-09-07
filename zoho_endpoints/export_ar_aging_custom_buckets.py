"""
Export unpaid invoices into custom AR aging buckets.

Buckets (non-overlapping; day 15 stays in 1-15, so the next band is 16-30):
  - 1-15
  - 16-30   (your "15-30", without double-counting day 15)
  - 31-60
  - 61-270
  - >270

Source: GET /reports/aragingdetails (all pages) + GET /salespersons for names.
Age uses Zoho's default for this report: invoice due date.
Current / 0-day invoices are excluded from the bucket sheets (listed on "Current_0").

Read-only. Writes Excel + JSON under zoho_endpoints/ar_aging_exports/.

Usage:
    python export_ar_aging_custom_buckets.py
"""
from __future__ import annotations

import json
import os
import time
from datetime import date, datetime
from pathlib import Path

import requests
from dotenv import load_dotenv
from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env_zoho")

CLIENT_ID = os.environ["ZOHO_CLIENT_ID"]
CLIENT_SECRET = os.environ["ZOHO_CLIENT_SECRET"]
REFRESH_TOKEN = os.environ["ZOHO_REFRESH_TOKEN"]
ORG_ID = os.environ["ZOHO_ORG_ID"]
TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"

OUT_DIR = Path(__file__).resolve().parent / "ar_aging_exports"
OUT_DIR.mkdir(parents=True, exist_ok=True)

TODAY = date.today().isoformat()

# (sheet_label, min_age inclusive, max_age inclusive or None for open-ended)
BUCKETS = [
    ("1-15", 1, 15),
    ("16-30", 16, 30),
    ("31-60", 31, 60),
    ("61-270", 61, 270),
    (">270", 271, None),
]

COLUMNS = [
    "customer_name",
    "salesperson_name",
    "invoice_number",
    "invoice_date",
    "due_date",
    "age_days",
    "bucket",
    "balance",
    "amount",
    "status",
    "customer_id",
    "invoice_id",
    "salesperson_id",
]


def get_token() -> str:
    r = requests.post(
        TOKEN_URL,
        params={
            "grant_type": "refresh_token",
            "refresh_token": REFRESH_TOKEN,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        },
        timeout=30,
    )
    data = r.json()
    if "access_token" not in data:
        raise RuntimeError(f"OAuth failed: {data}")
    return data["access_token"]


def fetch_salespersons(session: requests.Session) -> dict[str, str]:
    """Map salesperson_id -> salesperson_name."""
    r = session.get(
        f"{API_BASE}/salespersons",
        params={"organization_id": ORG_ID},
        timeout=60,
    )
    body = r.json()
    if r.status_code != 200 or body.get("code") not in (0, None):
        # Fallback: /users sometimes carries names for salesperson ids
        print(f"[warn] /salespersons failed: HTTP {r.status_code} {body.get('message')}")
        return {}

    rows = body.get("data") or body.get("salespersons") or []
    mapping: dict[str, str] = {}
    for row in rows:
        sid = str(row.get("salesperson_id") or row.get("user_id") or "")
        name = row.get("salesperson_name") or row.get("name") or ""
        if sid:
            mapping[sid] = name
    print(f"[OK] salespersons: {len(mapping)}")
    return mapping


def walk_invoices(node, out: list[dict]) -> None:
    if isinstance(node, dict):
        if node.get("entity") == "invoice":
            out.append(node)
        for v in node.values():
            walk_invoices(v, out)
    elif isinstance(node, list):
        for item in node:
            walk_invoices(item, out)


def fetch_all_aging_details(session: requests.Session) -> list[dict]:
    """Paginate AR Aging Details until exhausted."""
    page = 1
    by_id: dict[str, dict] = {}
    while True:
        params = {
            "organization_id": ORG_ID,
            "group_by": "customer",
            "to_date": TODAY,
            # Zoho AR default; omit also works — page_context shows invoiceduedate
            "aging_by": "invoiceduedate",
            "page": page,
            "per_page": 200,
        }
        t0 = time.time()
        r = session.get(f"{API_BASE}/reports/aragingdetails", params=params, timeout=120)
        ms = round((time.time() - t0) * 1000)
        body = r.json()
        if r.status_code != 200 or body.get("code") != 0:
            raise RuntimeError(f"aragingdetails page {page} failed: HTTP {r.status_code} {body}")

        rows: list[dict] = []
        walk_invoices(body.get("invoiceaging", {}), rows)
        for inv in rows:
            by_id[str(inv["id"])] = inv

        pc = body.get("page_context") or {}
        print(
            f"  page {page}: +{len(rows)} invoices "
            f"(unique={len(by_id)}) {ms}ms has_more={pc.get('has_more_page')} "
            f"aging_by={pc.get('aging_by')}"
        )
        if not pc.get("has_more_page"):
            break
        page += 1
        if page > 500:
            raise RuntimeError("safety stop: >500 pages")
    return list(by_id.values())


def age_days(inv: dict) -> int:
    raw = inv.get("age")
    if raw in (None, ""):
        return 0
    try:
        return int(raw)
    except (TypeError, ValueError):
        return 0


def bucket_for(age: int) -> str | None:
    if age <= 0:
        return "Current_0"
    for label, lo, hi in BUCKETS:
        if age < lo:
            continue
        if hi is None or age <= hi:
            return label
    return None


def normalize(inv: dict, sp_map: dict[str, str]) -> dict:
    sid = str(inv.get("salesperson_id") or "") or ""
    age = age_days(inv)
    return {
        "customer_name": inv.get("customer_name") or "",
        "salesperson_name": sp_map.get(sid) or inv.get("salesperson_name") or "",
        "invoice_number": inv.get("transaction_number") or "",
        "invoice_date": inv.get("date") or "",
        "due_date": inv.get("due_date") or "",
        "age_days": age,
        "bucket": bucket_for(age) or "",
        "balance": float(inv.get("balance") or 0),
        "amount": float(inv.get("amount") or 0),
        "status": inv.get("status") or "",
        "customer_id": str(inv.get("customer_id") or ""),
        "invoice_id": str(inv.get("id") or ""),
        "salesperson_id": sid,
    }


def write_excel(rows: list[dict], path: Path) -> None:
    wb = Workbook()
    # Summary first
    ws_sum = wb.active
    ws_sum.title = "Summary"
    ws_sum.append(["bucket", "invoice_count", "balance_sum"])
    for cell in ws_sum[1]:
        cell.font = Font(bold=True)

    by_bucket: dict[str, list[dict]] = {}
    for row in rows:
        by_bucket.setdefault(row["bucket"] or "unbucketed", []).append(row)

    order = [b[0] for b in BUCKETS] + ["Current_0", "unbucketed"]
    for label in order:
        items = by_bucket.get(label, [])
        bal = round(sum(r["balance"] for r in items), 2)
        ws_sum.append([label, len(items), bal])

    for label in order:
        items = by_bucket.get(label, [])
        if not items and label == "unbucketed":
            continue
        # Excel sheet title max 31 chars
        title = label[:31]
        ws = wb.create_sheet(title)
        ws.append(COLUMNS)
        for cell in ws[1]:
            cell.font = Font(bold=True)
        items_sorted = sorted(
            items,
            key=lambda r: (r["customer_name"], r["age_days"], r["invoice_number"]),
        )
        for r in items_sorted:
            ws.append([r[c] for c in COLUMNS])
        for i, _ in enumerate(COLUMNS, start=1):
            ws.column_dimensions[get_column_letter(i)].width = 18

    # All unpaid in one sheet
    ws_all = wb.create_sheet("All_Unpaid")
    ws_all.append(COLUMNS)
    for cell in ws_all[1]:
        cell.font = Font(bold=True)
    for r in sorted(rows, key=lambda x: (x["bucket"], x["customer_name"], x["age_days"])):
        ws_all.append([r[c] for c in COLUMNS])
    for i, _ in enumerate(COLUMNS, start=1):
        ws_all.column_dimensions[get_column_letter(i)].width = 18

    wb.save(path)


def main() -> None:
    print(f"Org {ORG_ID}  as_of {TODAY}")
    print("Buckets: 1-15 | 16-30 | 31-60 | 61-270 | >270  (age by invoice due date)")
    token = get_token()
    session = requests.Session()
    session.headers.update({"Authorization": f"Zoho-oauthtoken {token}"})

    sp_map = fetch_salespersons(session)
    print("Fetching AR Aging Details (all pages)...")
    raw = fetch_all_aging_details(session)
    # Unpaid only: balance > 0 (report already focuses on outstanding)
    unpaid = [inv for inv in raw if float(inv.get("balance") or 0) > 0]
    rows = [normalize(inv, sp_map) for inv in unpaid]

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = OUT_DIR / f"ar_aging_custom_{stamp}.json"
    xlsx_path = OUT_DIR / f"ar_aging_custom_{stamp}.xlsx"

    payload = {
        "as_of": TODAY,
        "organization_id": ORG_ID,
        "source": "GET /reports/aragingdetails?group_by=customer&aging_by=invoiceduedate",
        "buckets": [b[0] for b in BUCKETS],
        "note": "Second band labeled 16-30 (non-overlapping) for your requested 15-30.",
        "invoice_count": len(rows),
        "invoices": rows,
    }
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    write_excel(rows, xlsx_path)

    print()
    print(f"Unpaid invoices: {len(rows)}")
    for label, lo, hi in BUCKETS:
        items = [r for r in rows if r["bucket"] == label]
        bal = sum(r["balance"] for r in items)
        print(f"  {label:<8} {len(items):5d} invoices  balance {bal:,.2f}")
    current = [r for r in rows if r["bucket"] == "Current_0"]
    print(f"  {'Current_0':<8} {len(current):5d} invoices  balance {sum(r['balance'] for r in current):,.2f}")
    missing_sp = sum(1 for r in rows if not r["salesperson_name"])
    print(f"Missing salesperson name: {missing_sp}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")


if __name__ == "__main__":
    main()
