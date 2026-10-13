"""Cashflow forecast as a daily balance.

Opening cash is the sum of leaf bank and cash accounts. Later movements are
dated on the day cash is expected to move, in base currency (× exchange_rate):

- Accounts receivable: the invoice due date, when the customer's credit ends.
- Accounts payable: the bill due date, when the vendor's credit ends.
- Purchase order: unbilled goods. Received quantity is payable on the first
  receipt date plus the vendor's payment terms. Quantity not yet received is
  payable on the delivery date plus those terms.
- Sales order: uninvoiced amount, on the shipment date plus the customer's
  payment terms.

A date before as_of is overdue and lands on as_of. The running balance on a
day is the opening plus every signed movement on or before that day.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

_SKIP = {"void", "draft", "cancelled"}
_CLOSED_SO = {"void", "draft", "cancelled", "invoiced", "closed"}


def _f(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _r(value: float) -> float:
    return round(value, 2) + 0.0


def _day(value: Any) -> str | None:
    text = str(value or "")[:10]
    if len(text) == 10 and text[4] == "-" and text[7] == "-":
        try:
            date.fromisoformat(text)
        except ValueError:
            return None
        return text
    return None


def _terms(doc: dict) -> int:
    try:
        return max(0, int(float(doc.get("payment_terms") or 0)))
    except (TypeError, ValueError):
        return 0


def _fx(doc: dict) -> float:
    fx = _f(doc.get("exchange_rate"))
    return fx if fx else 1.0


def _plus(iso: str, days: int) -> str:
    return (date.fromisoformat(iso) + timedelta(days=days)).isoformat()


def _status(doc: dict) -> str:
    return str(doc.get("status") or "").lower()


def opening_accounts(accounts: list[dict]) -> tuple[float, list[dict]]:
    """Leaf bank and cash balances. Parents are skipped so cash is not counted twice."""
    parents = {str(a.get("parent_account_id") or "") for a in accounts}
    parents.discard("")
    rows = []
    for account in accounts:
        if account.get("account_type") not in ("bank", "cash"):
            continue
        if account.get("is_child_present") or str(account.get("account_id") or "") in parents:
            continue
        balance = _r(_f(account.get("current_balance")))
        if balance == 0:
            continue
        rows.append({
            "name": account.get("account_name") or "",
            "type": account.get("account_type"),
            "balance": balance,
        })
    rows.sort(key=lambda row: (row["type"], row["name"]))
    return _r(sum(row["balance"] for row in rows)), rows


def _place(when: str | None, as_of: date) -> tuple[str | None, bool]:
    """Return (cash date, overdue). None stays unscheduled."""
    if not when:
        return None, False
    if when < as_of.isoformat():
        return as_of.isoformat(), True
    return when, False


def _event(kind: str, when: str, overdue: bool, source: str | None, amount: float,
           party: str, number: str, label: str) -> dict:
    return {
        "date": when,
        "source_date": source or when,
        "overdue": overdue,
        "kind": kind,
        "amount": _r(amount),
        "party": party,
        "number": number,
        "label": label,
    }


def invoice_events(invoices: list[dict], as_of: date) -> tuple[list[dict], list[dict]]:
    events, pending = [], []
    for doc in invoices:
        if _status(doc) in _SKIP | {"paid"}:
            continue
        amount = _r(_f(doc.get("balance")) * _fx(doc))
        if amount <= 0:
            continue
        number = str(doc.get("invoice_number") or doc.get("number") or "")
        party = str(doc.get("customer_name") or "")
        when, overdue = _place(_day(doc.get("due_date")), as_of)
        if when is None:
            pending.append({"kind": "ar", "number": number, "party": party, "amount": amount,
                            "reason": "Invoice has a balance and no due date"})
            continue
        events.append(_event("ar", when, overdue, _day(doc.get("due_date")), amount, party, number, "Invoice due"))
    return events, pending


def bill_events(bills: list[dict], as_of: date) -> tuple[list[dict], list[dict]]:
    events, pending = [], []
    for doc in bills:
        if _status(doc) in _SKIP | {"paid"}:
            continue
        amount = _r(_f(doc.get("balance")) * _fx(doc))
        if amount <= 0:
            continue
        number = str(doc.get("bill_number") or "")
        party = str(doc.get("vendor_name") or "")
        when, overdue = _place(_day(doc.get("due_date")), as_of)
        if when is None:
            pending.append({"kind": "ap", "number": number, "party": party, "amount": -amount,
                            "reason": "Bill has a balance and no due date"})
            continue
        events.append(_event("ap", when, overdue, _day(doc.get("due_date")), -amount, party, number, "Bill due"))
    return events, pending


def _line_open(doc: dict, billed_key: str) -> tuple[float, float, float]:
    """Return (open amount, received-or-shipped open amount, not-yet open amount) in document currency.

    Open amount is grossed up from line item_total to the document total
    (tax, discount, adjustment) by total / sub_total.
    """
    sub = _f(doc.get("sub_total"))
    total = _f(doc.get("total"))
    factor = (total / sub) if sub else 1.0
    open_amount = received_open = 0.0
    for line in doc.get("line_items") or []:
        qty = _f(line.get("quantity"))
        if qty <= 0:
            continue
        open_qty = qty - _f(line.get(billed_key)) - _f(line.get("quantity_cancelled"))
        if open_qty <= 0:
            continue
        gross = _f(line.get("item_total")) * open_qty / qty * factor
        open_amount += gross
        received = _f(line.get("quantity_received"))
        if "quantity_received" in line:
            got = min(open_qty, max(0.0, received - _f(line.get(billed_key))))
            received_open += gross * got / open_qty
    if doc.get("bills") or doc.get("invoices"):
        covered = 0.0
        for link in (doc.get("bills") or doc.get("invoices") or []):
            if str(link.get("status") or "").lower() in _SKIP:
                continue
            covered += _f(link.get("total"))
        cap = max(0.0, total - covered)
        if open_amount > cap:
            scale = cap / open_amount if open_amount else 0.0
            open_amount *= scale
            received_open *= scale
    received_open = min(received_open, open_amount)
    return open_amount, received_open, open_amount - received_open


def purchase_order_events(orders: list[dict], as_of: date) -> tuple[list[dict], list[dict]]:
    events, pending = [], []
    for doc in orders:
        if _status(doc) in _SKIP | {"billed"}:
            continue
        open_amount, received_open, pending_open = _line_open(doc, "quantity_billed")
        fx = _fx(doc)
        number = str(doc.get("purchaseorder_number") or "")
        party = str(doc.get("vendor_name") or "")
        terms = _terms(doc)
        receives = [
            _day(item.get("date"))
            for item in (doc.get("purchasereceives") or [])
            if str(item.get("status") or "").lower() not in _SKIP and _day(item.get("date"))
        ]
        receipt = min(receives) if receives else None
        delivery = _day(doc.get("delivery_date")) or _day(doc.get("expected_delivery_date"))

        def add(portion: float, anchor: str | None, label: str) -> None:
            amount = _r(portion * fx)
            if amount <= 0:
                return
            if anchor is None:
                pending.append({"kind": "po", "number": number, "party": party, "amount": -amount,
                                "reason": "Purchase order is unbilled and has no receipt or delivery date"})
                return
            cash = _plus(anchor, terms)
            when, overdue = _place(cash, as_of)
            assert when is not None
            events.append(_event("po", when, overdue, cash, -amount, party, number, label))

        # Quantity not yet received has no receipt date. A missing quantity_received
        # key means the document does not say, so the whole open amount follows delivery.
        knows_receipt = any("quantity_received" in line for line in (doc.get("line_items") or []))
        if knows_receipt:
            add(received_open, receipt or delivery, "Purchase order received, not billed")
            add(pending_open, delivery, "Purchase order delivery")
        else:
            add(open_amount, delivery, "Purchase order delivery")
    return events, pending


def sales_order_events(orders: list[dict], as_of: date) -> tuple[list[dict], list[dict]]:
    events, pending = [], []
    for doc in orders:
        if _status(doc) in _CLOSED_SO:
            continue
        open_amount, _, _ = _line_open(doc, "quantity_invoiced")
        amount = _r(open_amount * _fx(doc))
        if amount <= 0:
            continue
        number = str(doc.get("salesorder_number") or "")
        party = str(doc.get("customer_name") or "")
        shipment = _day(doc.get("shipment_date")) or _day(doc.get("expected_shipment_date"))
        if shipment is None:
            pending.append({"kind": "so", "number": number, "party": party, "amount": amount,
                            "reason": "Sales order is uninvoiced and has no shipment date"})
            continue
        cash = _plus(shipment, _terms(doc))
        when, overdue = _place(cash, as_of)
        assert when is not None
        events.append(_event(
            "so", when, overdue, cash, amount, party, number, "Sales order delivery",
        ))
    return events, pending


def balances(opening: float, events: list[dict], start: date, end: date) -> list[dict]:
    """End-of-day balance. Movements before `start` are already inside `opening`."""
    if end < start:
        raise ValueError("end is before start")
    flow_by_day: dict[str, float] = {}
    for event in events:
        flow_by_day[event["date"]] = _r(flow_by_day.get(event["date"], 0.0) + event["amount"])
    rows = []
    balance = opening
    day = start
    while day <= end:
        iso = day.isoformat()
        flow = flow_by_day.get(iso, 0.0)
        balance = _r(balance + flow)
        rows.append({"date": iso, "flow": _r(flow), "balance": balance})
        day += timedelta(days=1)
    return rows


def forecast_from_documents(
    *,
    as_of: date,
    currency: str,
    organization: str,
    accounts: list[dict],
    invoices: list[dict] | None = None,
    bills: list[dict] | None = None,
    purchase_orders: list[dict] | None = None,
    sales_orders: list[dict] | None = None,
    mode: str,
    notes: list[str],
) -> dict[str, Any]:
    opening, account_rows = opening_accounts(accounts)
    events: list[dict] = []
    pending: list[dict] = []
    for loader, docs in (
        (invoice_events, invoices or []),
        (bill_events, bills or []),
        (purchase_order_events, purchase_orders or []),
        (sales_order_events, sales_orders or []),
    ):
        found, missing = loader(docs, as_of)
        events.extend(found)
        pending.extend(missing)
    events.sort(key=lambda row: (row["date"], row["kind"], row["number"], row["party"]))
    counts = {kind: sum(1 for row in events if row["kind"] == kind) for kind in ("ar", "ap", "po", "so")}
    totals = {
        kind: _r(sum(row["amount"] for row in events if row["kind"] == kind))
        for kind in ("ar", "ap", "po", "so")
    }
    return {
        "as_of": as_of.isoformat(),
        "currency": currency or "AED",
        "organization": organization,
        "mode": mode,
        "opening": opening,
        "accounts": account_rows,
        "events": events,
        "unscheduled": pending,
        "counts": counts,
        "totals": totals,
        "notes": notes,
        "built_at": datetime.now().isoformat(timespec="seconds"),
    }


def _read_json_dir(path: Path) -> list[dict]:
    if not path.is_dir():
        return []
    docs = []
    for file in sorted(path.glob("*.json")):
        try:
            doc = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict):
            docs.append(doc)
    return docs


def load_offline(coa_path: Path, cache_dir: Path, as_of: date) -> dict[str, Any]:
    """Build the forecast from the COA snapshot and cached documents. No network."""
    if not coa_path.is_file():
        raise FileNotFoundError(f"Chart of accounts snapshot not found: {coa_path}")
    snapshot = json.loads(coa_path.read_text(encoding="utf-8"))
    invoices = _read_json_dir(cache_dir / "invoices")
    sales_orders = _read_json_dir(cache_dir / "salesorders")
    notes = [
        "Bank and cash are leaf balances from the chart-of-accounts snapshot, not a live bank feed.",
        "Bills are outflows on the due date. A purchase order is an outflow for unbilled goods: "
        "received quantity on the first receipt plus the vendor's payment terms, and quantity "
        "still to arrive on the delivery date plus those terms.",
        "A sales order is an inflow for the uninvoiced amount on the shipment date plus the customer's payment terms.",
        "Anything dated before today is overdue and is placed on the first day.",
        "Each step on the timeline is a calendar day. The balance is the position after that day's movements.",
    ]
    if not invoices:
        notes.append("No cached invoices, so accounts receivable is empty.")
    if not sales_orders:
        notes.append("No cached sales orders, so sales-order deliveries are empty.")
    notes.append("This view reads local files only.")
    return forecast_from_documents(
        as_of=as_of,
        currency=str(snapshot.get("currency_code") or "AED"),
        organization=str(snapshot.get("organization_name") or ""),
        accounts=list(snapshot.get("accounts") or []),
        invoices=invoices,
        bills=_read_json_dir(cache_dir / "bills"),
        purchase_orders=_read_json_dir(cache_dir / "purchaseorders"),
        sales_orders=sales_orders,
        mode="cache",
        notes=notes,
    )
