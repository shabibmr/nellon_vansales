"""Purchases by line from Zoho bills and purchase orders.

    GET /bills?date_start=&date_end=              (list, paginated)  → GET /bills/{id}
    GET /purchaseorders?date_start=&date_end=     (list, paginated)  → GET /purchaseorders/{id}

Details are cached under output/cache/{bills,purchaseorders}/ and re-fetched only when the
list row's `last_modified_time` changes. `--offline` builds from cache with no Zoho calls.
Amounts are in base currency (× `exchange_rate`), line `item_total` (before bill-level tax).
Void/draft/cancelled documents are skipped.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path
from typing import Any

from reports.invoice_margin import MarginSource, _f
from zoho_client import ZohoClient

COLUMNS = [
    "month", "date", "kind", "number", "vendor_name", "status", "item_name", "sku", "unit",
    "quantity", "rate", "amount", "doc_id", "item_id",
]
SUMMARY_COLUMNS = ["key", "documents", "lines", "quantity", "amount"]
SUMMARY_DIMENSIONS = {"By Month": "month", "By Vendor": "vendor_name", "By Item": "item_name", "By Kind": "kind"}

SKIP_STATUSES = {"void", "draft", "cancelled"}
KINDS = {
    "bill": ("/bills", "bills", "bill", "bill_id", "bill_number"),
    "purchase_order": ("/purchaseorders", "purchaseorders", "purchaseorder", "purchaseorder_id", "purchaseorder_number"),
}


class PurchaseSource(MarginSource):
    def documents(self, kind: str, from_date: str, to_date: str) -> list[dict]:
        endpoint, list_key, detail_key, id_key, _ = KINDS[kind]
        cache = self.inv_dir.parent / list_key
        cache.mkdir(parents=True, exist_ok=True)
        if self.client is None:
            docs = [self._read(p) for p in sorted(cache.glob("*.json"))]
            return [
                d for d in docs
                if d and from_date <= str(d.get("date", "")) <= to_date
                and str(d.get("status", "")).lower() not in SKIP_STATUSES
            ]
        listed = self._paged(endpoint, list_key, {"date_start": from_date, "date_end": to_date})
        listed = [d for d in listed if str(d.get("status", "")).lower() not in SKIP_STATUSES]
        print(f"  {list_key} in range: {len(listed)}")
        out = []
        for n, head in enumerate(listed, 1):
            path = cache / f"{head[id_key]}.json"
            cached = self._read(path)
            if cached and cached.get("last_modified_time") == head.get("last_modified_time"):
                out.append(cached)
                continue
            detail = self._get(f"{endpoint}/{head[id_key]}").get(detail_key) or {}
            self._write(path, detail)
            out.append(detail)
            if n % 50 == 0:
                print(f"  fetched {n}/{len(listed)} {list_key} details…")
        return out


def build_purchase_rows(kind: str, docs: list[dict]) -> list[dict[str, Any]]:
    id_key, num_key = KINDS[kind][3], KINDS[kind][4]
    rows = []
    for d in docs:
        fx = _f(d.get("exchange_rate")) or 1.0
        date = str(d.get("date") or "")
        for ln in d.get("line_items") or []:
            rows.append({
                "month": date[:7], "date": date, "kind": kind, "number": d.get(num_key, ""),
                "vendor_name": d.get("vendor_name", ""), "status": d.get("status", ""),
                "item_name": ln.get("name") or ln.get("description", ""), "sku": ln.get("sku", ""),
                "unit": ln.get("unit", ""), "quantity": round(_f(ln.get("quantity")), 4),
                "rate": round(_f(ln.get("rate")) * fx, 4), "amount": round(_f(ln.get("item_total")) * fx, 2),
                "doc_id": str(d.get(id_key) or ""), "item_id": str(ln.get("item_id") or ""),
            })
    return rows


def summarise(rows: list[dict[str, Any]], key: str) -> list[dict[str, Any]]:
    agg: dict[str, dict[str, Any]] = {}
    for r in rows:
        a = agg.setdefault(str(r.get(key) or "(none)"), {"docs": set(), "lines": 0, "quantity": 0.0, "amount": 0.0})
        a["docs"].add((r["kind"], r["doc_id"]))
        a["lines"] += 1
        a["quantity"] += r["quantity"]
        a["amount"] += r["amount"]
    out = [{"key": k, "documents": len(a["docs"]), "lines": a["lines"],
            "quantity": round(a["quantity"], 4), "amount": round(a["amount"], 2)} for k, a in agg.items()]
    return sorted(out, key=(lambda r: r["key"]) if key == "month" else (lambda r: r["amount"]), reverse=key != "month")


def generate_purchases(
    source: PurchaseSource, from_date: str, to_date: str, kinds: list[str] | None = None,
    log: Callable[[str], None] = print,
) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]], dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    counts = {}
    for kind in kinds or list(KINDS):
        log(f"{kind} {from_date} → {to_date}{' (cache only)' if source.client is None else ''}…")
        docs = source.documents(kind, from_date, to_date)
        counts[kind] = len(docs)
        rows += build_purchase_rows(kind, docs)
    rows.sort(key=lambda r: (r["date"], r["kind"], r["number"]))
    summaries = {name: summarise(rows, key) for name, key in SUMMARY_DIMENSIONS.items()}
    summary = {
        "from_date": from_date, "to_date": to_date, "documents": counts, "lines": len(rows),
        "amount_by_kind": {k: round(sum(r["amount"] for r in rows if r["kind"] == k), 2) for k in counts},
        "api_calls": source.api_calls,
    }
    return rows, summaries, summary
