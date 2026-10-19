"""Shared helpers for the zoho-koyson seed scripts (purchases, notes, contacts).

Money rules follow proposal/DB-Schema-Proposed.md ("Sales money", "COGS").
"""

from __future__ import annotations

import json
import os
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / ".env.mis")

CENT = Decimal("0.01")


def connect(db: str) -> pymysql.Connection:
    return pymysql.connect(
        host=os.getenv("MIS_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("MIS_DB_PORT", "3306")),
        user=os.getenv("MIS_DB_USER", "user2grey"),
        password=os.getenv("MIS_DB_PASSWORD", "user2grey"),
        database=db,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def d(val: Any, default: str = "0") -> Decimal:
    if val is None or val == "":
        return Decimal(default)
    try:
        return Decimal(str(val))
    except Exception:
        return Decimal(default)


def cents(val: Decimal) -> Decimal:
    return val.quantize(CENT, rounding=ROUND_HALF_UP)


def s(val: Any, limit: int) -> str:
    return str(val if val is not None else "").strip()[:limit]


def parse_date(val: Any) -> date | None:
    text = str(val or "").strip()[:10]
    try:
        return datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        return None


def parse_dt(val: Any) -> str | None:
    text = str(val or "").strip()
    return text[:19].replace("T", " ") if len(text) >= 19 else None


def prorate(total: Decimal, weights: list[Decimal]) -> list[Decimal]:
    """Split total across weights to the cent; the remainder goes to the largest weight."""
    if not weights:
        return []
    wsum = sum(weights)
    if wsum <= 0:
        shares = [cents(total / len(weights)) for _ in weights]
    else:
        shares = [cents(total * w / wsum) for w in weights]
    rem = total - sum(shares)
    if rem:
        big = max(range(len(weights)), key=lambda i: weights[i])
        shares[big] += rem
    return shares


def unwrap(obj: Any, key: str) -> dict | None:
    """Cache files are either {key: {...}} or the document itself."""
    if not isinstance(obj, dict):
        return None
    inner = obj.get(key)
    if isinstance(inner, dict):
        return inner
    return obj if "line_items" in obj else None


def read_cache(folder: Path, key: str) -> list[dict]:
    docs = []
    for f in sorted(folder.glob("*.json")):
        if f.name.startswith("_"):
            continue
        try:
            doc = unwrap(json.loads(f.read_text(encoding="utf-8")), key)
        except (OSError, ValueError):
            continue
        if doc is not None:
            docs.append(doc)
    return docs


def load_item_units(cur) -> dict[str, tuple[str, Decimal]]:
    cur.execute("SELECT unit_conversion_id, item_id, conversion_rate FROM item_units")
    return {r["unit_conversion_id"]: (r["item_id"], Decimal(r["conversion_rate"])) for r in cur.fetchall()}


def load_item_rates(cur) -> dict[str, Decimal]:
    cur.execute("SELECT item_id, purchase_rate FROM items")
    return {r["item_id"]: Decimal(r["purchase_rate"] or 0) for r in cur.fetchall()}


def resolve_conversion(line: dict, units: dict) -> tuple[Decimal, str]:
    """Returns (conversion_rate, flag). Flag is '' when the conversion is known."""
    ucid = line.get("unit_conversion_id")
    if ucid:
        if ucid in units:
            return units[ucid][1], ""
        return Decimal("1"), "unknown unit conversion"
    conv = d(line.get("conversion_rate"), "1")
    return (conv if conv > 0 else Decimal("1")), ""


def doc_money(header: dict, lines: list[dict]) -> list[dict]:
    """Per-line money for an invoice-like document.

    net amount (AED) = (ex-tax line amount - share of document discount) x exchange_rate.
    Line discount is derived from qty x rate - item_total, so it covers item-level discounts.
    A tax-inclusive document has its tax removed before the split, and the document
    discount is scaled by the same ex-tax ratio.
    """
    xr = d(header.get("exchange_rate"), "1") or Decimal("1")
    incl = bool(header.get("is_inclusive_tax"))
    item_level = header.get("discount_type") == "item_level"
    doc_disc = Decimal("0") if item_level else d(header.get("discount_total"))

    rows = []
    for ln in lines:
        qty, rate, total = d(ln.get("quantity")), d(ln.get("rate")), d(ln.get("item_total"))
        pct = d(ln.get("tax_percentage"))
        ratio = Decimal("1") / (Decimal("1") + pct / 100) if incl and pct else Decimal("1")
        line_disc = max(cents(qty * rate) - cents(total), Decimal("0"))
        rows.append(
            {
                "item_total": cents(total),
                "line_disc_ex": line_disc * ratio,
                "ex_total": total * ratio,
                "pct": pct,
                "tax_given": ln.get("tax_amount"),
            }
        )
    sum_incl = sum(d(ln.get("item_total")) for ln in lines)
    sum_ex = sum(r["ex_total"] for r in rows)
    doc_disc_ex = doc_disc * (sum_ex / sum_incl) if incl and sum_incl else doc_disc
    shares = prorate(cents(doc_disc_ex), [r["ex_total"] for r in rows])

    out = []
    for r, share in zip(rows, shares):
        if r["tax_given"] is not None:
            tax = cents(d(r["tax_given"]))
        elif incl:
            tax = cents(r["item_total"] - r["ex_total"])
        else:
            tax = cents(r["ex_total"] * r["pct"] / 100)
        out.append(
            {
                "item_total": r["item_total"],
                "tax_amount": tax,
                "line_discount": cents(r["line_disc_ex"] * xr),
                "doc_discount": cents(share * xr),
                "amount": cents((r["ex_total"] - share) * xr),
            }
        )
    return out


def line_cogs(
    qty: Decimal, conv: Decimal, base_qty: Decimal, price: Decimal, master_rate: Decimal,
    base_unit: str, credit_only: bool = False,
) -> tuple[Decimal, str]:
    """COGS per the schema doc. Returns (cogs, flag)."""
    if credit_only:
        return Decimal("0.00"), ""
    if price <= 0:
        return cents(master_rate * base_qty), "purchase_price 0: used item master rate"
    if base_unit and conv > 1 and master_rate > 0:
        # A pack price is ~conv x the base rate; a base price is ~1x. Split at the geometric midpoint.
        if price / master_rate < conv.sqrt():
            return cents(qty * conv * price), ""
        return cents(qty * price), ""
    if base_unit and conv > 1 and master_rate <= 0:
        return cents(qty * price), "no master rate: price taken as pack price"
    return cents(qty * price), ""


def table_exists(cur, name: str) -> bool:
    cur.execute("SHOW TABLES LIKE %s", (name,))
    return cur.fetchone() is not None
