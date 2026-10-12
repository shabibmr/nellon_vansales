"""Revenue and margin by invoice line (template sheet "Margin").

One row per sales-invoice line item:

    month | date | invoice | customer | salesperson | van | item | unit | qty | base qty
    | rate | gross | line discount | invoice discount (allocated) | net sales
    | cost rate | cost | gross margin | GM %

Sources:

    GET /invoices?date_start=&date_end=    (list, paginated; void/draft skipped)
    GET /invoices/{id}                     (line items — list omits them)
    GET /items                             (purchase_rate per item)
    GET /items/{id}                        (unit_conversions, only for items sold in an alternate UOM)

Invoice and item details are cached under output/cache/ and only re-fetched when
the invoice's `last_modified_time` changes, so re-runs are cheap. `--offline`
builds purely from that cache with no Zoho calls.

Cost basis: the item's *current* `purchase_rate` × base quantity. That is a
standard-cost view; the P&L COGS from the ledger (weighted/FIFO) can differ.
Amounts are in base currency (invoice amounts × `exchange_rate`), net of tax.
Credit notes / returns are not netted here.
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from zoho_client import ZohoClient

COLUMNS = [
    "month",
    "date",
    "invoice_number",
    "customer_name",
    "salesperson_name",
    "van",
    "item_name",
    "sku",
    "unit",
    "quantity",
    "conversion_rate",
    "base_quantity",
    "rate",
    "gross_amount",
    "line_discount",
    "invoice_discount",
    "net_sales",
    "cost_rate",
    "cost",
    "gross_margin",
    "gross_margin_pct",
    "flag",
    "invoice_id",
    "item_id",
]

SUMMARY_COLUMNS = ["key", "lines", "base_quantity", "net_sales", "cost", "gross_margin", "gross_margin_pct"]
SUMMARY_DIMENSIONS = {
    "By Month": "month",
    "By Item": "item_name",
    "By Customer": "customer_name",
    "By Salesperson": "salesperson_name",
    "By Van": "van",
}

SKIP_STATUSES = {"void", "draft"}
MIN_SECONDS_BETWEEN_CALLS = 0.7  # Zoho Books allows ~100 requests/min per org


def _f(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


# ---------------------------------------------------------------------------
# Fetching (with on-disk cache)
# ---------------------------------------------------------------------------


class _Throttle:
    def __init__(self, min_interval: float) -> None:
        self.min_interval = min_interval
        self._last = 0.0

    def wait(self) -> None:
        delay = self._last + self.min_interval - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        self._last = time.monotonic()


class MarginSource:
    """Loads invoices/items from Zoho with a JSON cache; `client=None` → cache only."""

    def __init__(self, cache_dir: Path, client: ZohoClient | None) -> None:
        self.client = client
        self.inv_dir = cache_dir / "invoices"
        self.item_dir = cache_dir / "items"
        self.inv_dir.mkdir(parents=True, exist_ok=True)
        self.item_dir.mkdir(parents=True, exist_ok=True)
        self._throttle = _Throttle(MIN_SECONDS_BETWEEN_CALLS)
        self.api_calls = 0

    def _get(self, endpoint: str, params: dict[str, Any] | None = None) -> dict:
        assert self.client is not None
        self._throttle.wait()
        self.api_calls += 1
        return self.client.get(endpoint, params)

    def _paged(self, endpoint: str, key: str, params: dict[str, Any]) -> list[dict]:
        out, page = [], 1
        while True:
            body = self._get(endpoint, {**params, "page": page, "per_page": 200})
            out.extend(body.get(key) or [])
            if not (body.get("page_context") or {}).get("has_more_page"):
                return out
            page += 1

    @staticmethod
    def _read(path: Path) -> dict | None:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None

    @staticmethod
    def _write(path: Path, data: dict) -> None:
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data), encoding="utf-8")
        tmp.replace(path)

    def invoices(self, from_date: str, to_date: str) -> list[dict]:
        """Full invoice details (with line_items) dated within [from_date, to_date]."""
        if self.client is None:
            cached = [self._read(p) for p in sorted(self.inv_dir.glob("*.json"))]
            return [
                inv for inv in cached
                if inv and from_date <= str(inv.get("date", "")) <= to_date
                and str(inv.get("status", "")).lower() not in SKIP_STATUSES
            ]

        listed = self._paged("/invoices", "invoices", {"date_start": from_date, "date_end": to_date})
        listed = [i for i in listed if str(i.get("status", "")).lower() not in SKIP_STATUSES]
        print(f"  invoices in range: {len(listed)}")
        out = []
        for n, head in enumerate(listed, 1):
            invoice_id = str(head["invoice_id"])
            path = self.inv_dir / f"{invoice_id}.json"
            cached = self._read(path)
            if cached and cached.get("last_modified_time") == head.get("last_modified_time"):
                out.append(cached)
                continue
            detail = self._get(f"/invoices/{invoice_id}").get("invoice") or {}
            self._write(path, detail)
            out.append(detail)
            if n % 50 == 0:
                print(f"  fetched {n}/{len(listed)} invoice details…")
        return out

    def items(self) -> dict[str, dict]:
        """item_id → item (list fields: purchase_rate, sku, unit)."""
        path = self.item_dir / "_list.json"
        if self.client is None:
            return {str(i["item_id"]): i for i in (self._read(path) or {}).get("items", [])}
        items = self._paged("/items", "items", {})
        self._write(path, {"items": items})
        return {str(i["item_id"]): i for i in items}

    def conversions(self, item_ids: set[str]) -> dict[str, dict[str, float]]:
        """item_id → {unit_conversion_id: conversion_rate} for the given items."""
        out: dict[str, dict[str, float]] = {}
        for item_id in sorted(item_ids):
            path = self.item_dir / f"{item_id}.json"
            detail = self._read(path)
            if detail is None and self.client is not None:
                detail = self._get(f"/items/{item_id}").get("item") or {}
                self._write(path, detail)
            out[item_id] = {
                str(c.get("unit_conversion_id")): _f(c.get("conversion_rate")) or 1.0
                for c in (detail or {}).get("unit_conversions") or []
            }
        return out


# ---------------------------------------------------------------------------
# Pure build
# ---------------------------------------------------------------------------


def _line_net_of_tax(line: dict, inclusive: bool) -> float:
    total = _f(line.get("item_total"))
    if inclusive:
        pct = _f(line.get("tax_percentage"))
        total = total / (1 + pct / 100) if pct else total
    return total


def _invoice_discount(invoice: dict) -> float:
    """Entity-level (whole-invoice) discount in invoice currency; item-level is already in item_total."""
    if str(invoice.get("discount_type") or "").lower() == "item_level":
        return 0.0
    return _f(invoice.get("discount_amount") or invoice.get("discount_total"))


def build_margin_rows(
    invoices: list[dict],
    items: dict[str, dict],
    conversions: dict[str, dict[str, float]],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for inv in invoices:
        fx = _f(inv.get("exchange_rate")) or 1.0
        inclusive = bool(inv.get("is_inclusive_tax"))
        lines = [ln for ln in inv.get("line_items") or [] if ln.get("item_id") or ln.get("name")]
        nets = [_line_net_of_tax(ln, inclusive) for ln in lines]
        net_total = sum(nets)
        inv_discount = _invoice_discount(inv)
        if inclusive and inv_discount and net_total:
            gross_incl = sum(_f(ln.get("item_total")) for ln in lines) or net_total
            inv_discount *= net_total / gross_incl  # discount was entered tax-inclusive

        date = str(inv.get("date") or "")
        for ln, net in zip(lines, nets):
            item_id = str(ln.get("item_id") or "")
            item = items.get(item_id) or {}
            qty = _f(ln.get("quantity"))
            conv_id = str(ln.get("unit_conversion_id") or "")
            conv = conversions.get(item_id, {}).get(conv_id, 1.0) if conv_id else 1.0
            base_qty = qty * conv
            rate = _f(ln.get("rate"))
            gross = rate * qty
            if inclusive:
                pct = _f(ln.get("tax_percentage"))
                gross = gross / (1 + pct / 100) if pct else gross
            line_discount = gross - net
            alloc = inv_discount * (net / net_total) if net_total else 0.0
            net_sales = (net - alloc) * fx
            purchase_rate = _f(item.get("purchase_rate"))
            cost = purchase_rate * base_qty
            margin = net_sales - cost

            flags = []
            if not item_id:
                flags.append("no item")
            elif not item:
                flags.append("item not in item list")
            elif not purchase_rate:
                flags.append("no purchase rate")
            if conv_id and conv_id not in conversions.get(item_id, {}):
                flags.append("unknown unit conversion")

            rows.append(
                {
                    "month": date[:7],
                    "date": date,
                    "invoice_number": inv.get("invoice_number", ""),
                    "customer_name": inv.get("customer_name", ""),
                    "salesperson_name": inv.get("salesperson_name", "") or "(none)",
                    "van": ln.get("location_name") or inv.get("location_name") or "(none)",
                    "item_name": ln.get("name") or item.get("name", ""),
                    "sku": ln.get("sku") or item.get("sku", ""),
                    "unit": ln.get("unit") or item.get("unit", ""),
                    "quantity": round(qty, 4),
                    "conversion_rate": conv,
                    "base_quantity": round(base_qty, 4),
                    "rate": round(rate * fx, 4),
                    "gross_amount": round(gross * fx, 2),
                    "line_discount": round(line_discount * fx, 2),
                    "invoice_discount": round(alloc * fx, 2),
                    "net_sales": round(net_sales, 2),
                    "cost_rate": round(purchase_rate * conv, 4),
                    "cost": round(cost, 2),
                    "gross_margin": round(margin, 2),
                    "gross_margin_pct": round(margin / net_sales, 4) if net_sales else 0.0,
                    "flag": "; ".join(flags),
                    "invoice_id": str(inv.get("invoice_id") or ""),
                    "item_id": item_id,
                }
            )
    rows.sort(key=lambda r: (r["date"], r["invoice_number"]))
    return rows


def summarise(rows: list[dict[str, Any]], key: str) -> list[dict[str, Any]]:
    agg: dict[str, dict[str, Any]] = {}
    for r in rows:
        a = agg.setdefault(
            str(r.get(key) or "(none)"),
            {"lines": 0, "base_quantity": 0.0, "net_sales": 0.0, "cost": 0.0, "gross_margin": 0.0},
        )
        a["lines"] += 1
        for f in ("base_quantity", "net_sales", "cost", "gross_margin"):
            a[f] += r[f]
    out = []
    for k, a in agg.items():
        out.append(
            {
                "key": k,
                "lines": a["lines"],
                "base_quantity": round(a["base_quantity"], 4),
                "net_sales": round(a["net_sales"], 2),
                "cost": round(a["cost"], 2),
                "gross_margin": round(a["gross_margin"], 2),
                "gross_margin_pct": round(a["gross_margin"] / a["net_sales"], 4) if a["net_sales"] else 0.0,
            }
        )
    reverse = key != "month"
    return sorted(out, key=(lambda r: r["net_sales"]) if reverse else (lambda r: r["key"]), reverse=reverse)


def generate_invoice_margin(
    source: MarginSource,
    from_date: str,
    to_date: str,
    log: Callable[[str], None] = print,
) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]], dict[str, Any]]:
    log(f"Invoices {from_date} → {to_date}{' (cache only)' if source.client is None else ''}…")
    invoices = source.invoices(from_date, to_date)
    items = source.items()
    alt_unit_items = {
        str(ln.get("item_id"))
        for inv in invoices
        for ln in inv.get("line_items") or []
        if ln.get("unit_conversion_id") and ln.get("item_id")
    }
    conversions = source.conversions(alt_unit_items)
    rows = build_margin_rows(invoices, items, conversions)
    summaries = {name: summarise(rows, key) for name, key in SUMMARY_DIMENSIONS.items()}
    net = round(sum(r["net_sales"] for r in rows), 2)
    cost = round(sum(r["cost"] for r in rows), 2)
    summary = {
        "from_date": from_date,
        "to_date": to_date,
        "invoices": len(invoices),
        "lines": len(rows),
        "net_sales": net,
        "cost": cost,
        "gross_margin": round(net - cost, 2),
        "gross_margin_pct": round((net - cost) / net, 4) if net else 0.0,
        "flagged_lines": sum(1 for r in rows if r["flag"]),
        "api_calls": source.api_calls,
        "cost_basis": "item purchase_rate (current) x base quantity",
    }
    return rows, summaries, summary
