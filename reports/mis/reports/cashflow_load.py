"""Load a cashflow forecast from Zoho Books into MariaDB.

Calls, all GET:

- /chartofaccounts?showbalance=true and /organizations for bank and cash balances
- /invoices?status=unpaid
- /bills?status=unpaid
- /purchaseorders?status=open and partially_billed, then each open order
- /salesorders?status=open and partially_invoiced, then each open order

List rows are enough for invoices and bills when they carry balance, due date,
and an exchange rate. Purchase orders and sales orders need the detail, because
the unbilled or uninvoiced amount is on the lines. Details are cached under
output/cache and reused when last_modified_time has not changed.
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from datetime import date
from pathlib import Path
from typing import Any

from reports.cashflow_forecast import forecast_from_documents
from reports.category_master import fetch_coa_snapshot
from zoho_client import ZohoClient

MIN_SECONDS = 0.7

_LISTS = (
    ("invoices", "/invoices", "invoices", {"status": "unpaid"}),
    ("bills", "/bills", "bills", {"status": "unpaid"}),
    ("purchaseorders", "/purchaseorders", "purchaseorders", {"status": "open"}),
    ("purchaseorders", "/purchaseorders", "purchaseorders", {"status": "partially_billed"}),
    ("salesorders", "/salesorders", "salesorders", {"status": "open"}),
    ("salesorders", "/salesorders", "salesorders", {"status": "partially_invoiced"}),
)
_DETAIL = {
    "purchaseorders": ("/purchaseorders/{id}", "purchaseorder", "purchaseorder_id"),
    "salesorders": ("/salesorders/{id}", "salesorder", "salesorder_id"),
}
_ID_KEY = {
    "invoices": "invoice_id",
    "bills": "bill_id",
    "purchaseorders": "purchaseorder_id",
    "salesorders": "salesorder_id",
}


class _Throttle:
    def __init__(self, min_interval: float) -> None:
        self.min_interval = min_interval
        self._last = 0.0

    def wait(self) -> None:
        delay = self._last + self.min_interval - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        self._last = time.monotonic()


def _read(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    tmp.replace(path)


def _with_fx(row: dict, base: str) -> tuple[dict, bool]:
    """Return (row, needs_detail). Base-currency rows default the rate to 1."""
    currency = str(row.get("currency_code") or base or "").upper()
    if row.get("exchange_rate"):
        return row, False
    if not currency or currency == str(base or "").upper():
        return {**row, "exchange_rate": 1}, False
    return row, True


def load_from_zoho(
    client: ZohoClient,
    cache_dir: Path,
    as_of: date,
    log: Callable[[str], None] = print,
) -> tuple[dict[str, Any], str, int]:
    """Fetch the forecast inputs and build the payload. Returns (payload, org id, api calls)."""
    throttle = _Throttle(MIN_SECONDS)
    calls = 0

    def get(endpoint: str, params: dict | None = None) -> dict:
        nonlocal calls
        throttle.wait()
        calls += 1
        return client.get(endpoint, params)

    def paged(endpoint: str, key: str, params: dict) -> list[dict]:
        out, page = [], 1
        while True:
            body = get(endpoint, {**params, "page": page, "per_page": 200})
            out.extend(body.get(key) or [])
            if not (body.get("page_context") or {}).get("has_more_page"):
                return out
            page += 1

    log("chart of accounts…")
    throttle.wait()
    calls += 1
    snapshot = fetch_coa_snapshot(client)
    calls += 1  # organizations, issued inside fetch_coa_snapshot without our throttle
    base = str(snapshot.get("currency_code") or "")
    listed: dict[str, dict[str, dict]] = {kind: {} for kind in _ID_KEY}

    for kind, endpoint, key, params in _LISTS:
        try:
            rows = paged(endpoint, key, params)
        except RuntimeError as exc:
            log(f"  {kind} {params.get('status')}: skipped ({exc})")
            continue
        id_key = _ID_KEY[kind]
        for row in rows:
            listed[kind][str(row.get(id_key) or "")] = row
        log(f"  {kind} {params.get('status')}: {len(rows)}  (unique {len(listed[kind])})")

    def details(kind: str) -> list[dict]:
        template, envelope, id_key = _DETAIL[kind]
        folder = cache_dir / kind
        out = []
        rows = list(listed[kind].values())
        for n, head in enumerate(rows, 1):
            doc_id = str(head.get(id_key) or "")
            path = folder / f"{doc_id}.json"
            cached = _read(path)
            if cached and cached.get("last_modified_time") == head.get("last_modified_time"):
                out.append(cached)
                continue
            body = get(template.format(id=doc_id), None)
            doc = body.get(envelope) or body
            _write(path, doc)
            out.append(doc)
            if n % 25 == 0 or n == len(rows):
                log(f"  {kind} details {n}/{len(rows)}")
        return out

    def headers(kind: str) -> list[dict]:
        ready, pending = [], []
        for row in listed[kind].values():
            fixed, needs = _with_fx(row, base)
            (pending if needs else ready).append(fixed)
        if pending:
            template = "/invoices/{id}" if kind == "invoices" else "/bills/{id}"
            envelope = "invoice" if kind == "invoices" else "bill"
            id_key = _ID_KEY[kind]
            folder = cache_dir / kind
            log(f"  {kind}: {len(pending)} foreign documents need a detail for the exchange rate")
            for n, head in enumerate(pending, 1):
                doc_id = str(head.get(id_key) or "")
                path = folder / f"{doc_id}.json"
                cached = _read(path)
                if cached and cached.get("exchange_rate") and cached.get("last_modified_time") == head.get("last_modified_time"):
                    ready.append(cached)
                    continue
                doc = get(template.format(id=doc_id)).get(envelope) or {}
                _write(path, doc)
                ready.append(doc)
                if n % 25 == 0 or n == len(pending):
                    log(f"  {kind} fx details {n}/{len(pending)}")
        return ready

    log("purchase order and sales order details…")
    purchase_orders = details("purchaseorders")
    sales_orders = details("salesorders")
    invoices = headers("invoices")
    bills = headers("bills")

    notes = [
        "Bank and cash are leaf balances from GET /chartofaccounts?showbalance=true.",
        "Receivables are unpaid invoices, on the due date.",
        "Payables are unpaid bills, on the due date, when the vendor credit period ends.",
        "A purchase order is the unbilled amount: received quantity on the first receipt date plus the vendor's payment terms, and quantity still to arrive on the delivery date plus those terms.",
        "A sales order is the uninvoiced amount on the shipment date plus the customer's payment terms.",
        "Anything dated before the as-of day is overdue and is placed on the first day.",
        "Loaded from Zoho Books into MariaDB nellon_mis.",
    ]
    payload = forecast_from_documents(
        as_of=as_of,
        currency=base or "AED",
        organization=str(snapshot.get("organization_name") or ""),
        accounts=list(snapshot.get("accounts") or []),
        invoices=invoices,
        bills=bills,
        purchase_orders=purchase_orders,
        sales_orders=sales_orders,
        mode="zoho",
        notes=notes,
    )
    payload["api_calls"] = calls
    return payload, str(snapshot.get("organization_id") or client.org_id), calls
