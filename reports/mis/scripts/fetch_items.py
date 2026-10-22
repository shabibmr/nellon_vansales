"""Fetch every item from Zoho Books into MariaDB table `items`.

    GET /items?per_page=200&page=N   (all statuses)

One row per item_id, upserted, so re-running refreshes rows instead of
duplicating them. The full list response is kept in `raw_json`.

    python -m scripts.fetch_items                       # live Zoho call
    python -m scripts.fetch_items --from-json output/cache/items/_list.json   # no Zoho call
    python -m scripts.fetch_items --from-json output/cache/items/_list.json --dry-run   # no DB write either
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from common import db
TABLE = "items"

DDL = f"""
CREATE TABLE IF NOT EXISTS {TABLE} (
    item_id             VARCHAR(40)   NOT NULL,
    name                VARCHAR(255)  NOT NULL DEFAULT '',
    sku                 VARCHAR(120)  NOT NULL DEFAULT '',
    unit                VARCHAR(40)   NOT NULL DEFAULT '',
    status              VARCHAR(20)   NOT NULL DEFAULT '',
    item_type           VARCHAR(40)   NOT NULL DEFAULT '',
    product_type        VARCHAR(40)   NOT NULL DEFAULT '',
    brand               VARCHAR(120)  NOT NULL DEFAULT '',
    description         VARCHAR(1000) NOT NULL DEFAULT '',
    rate                DECIMAL(18,4) NOT NULL DEFAULT 0,
    purchase_rate       DECIMAL(18,4) NOT NULL DEFAULT 0,
    tax_id              VARCHAR(40)   NOT NULL DEFAULT '',
    tax_name            VARCHAR(120)  NOT NULL DEFAULT '',
    tax_percentage      DECIMAL(9,4)  NOT NULL DEFAULT 0,
    account_id          VARCHAR(40)   NOT NULL DEFAULT '',
    account_name        VARCHAR(255)  NOT NULL DEFAULT '',
    purchase_account_id VARCHAR(40)   NOT NULL DEFAULT '',
    purchase_account_name VARCHAR(255) NOT NULL DEFAULT '',
    track_inventory     TINYINT(1)    NOT NULL DEFAULT 0,
    can_be_sold         TINYINT(1)    NOT NULL DEFAULT 0,
    can_be_purchased    TINYINT(1)    NOT NULL DEFAULT 0,
    stock_on_hand       DECIMAL(18,4) NOT NULL DEFAULT 0,
    available_stock     DECIMAL(18,4) NOT NULL DEFAULT 0,
    created_time        DATETIME      NULL,
    last_modified_time  DATETIME      NULL,
    raw_json            LONGTEXT      NULL,
    fetched_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (item_id),
    KEY idx_name (name),
    KEY idx_sku (sku),
    KEY idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
"""

COLUMNS = [
    "item_id", "name", "sku", "unit", "status", "item_type", "product_type", "brand",
    "description", "rate", "purchase_rate", "tax_id", "tax_name", "tax_percentage",
    "account_id", "account_name", "purchase_account_id", "purchase_account_name",
    "track_inventory", "can_be_sold", "can_be_purchased", "stock_on_hand", "available_stock",
    "created_time", "last_modified_time", "raw_json",
]


def _f(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


def _s(val: Any, limit: int) -> str:
    return str(val if val is not None else "")[:limit]


def _dt(val: Any) -> str | None:
    # Zoho: 2026-04-01T12:32:26+0400 -> keep the local wall-clock part.
    return str(val)[:19].replace("T", " ") if val else None


def to_row(i: dict[str, Any]) -> dict[str, Any]:
    return {
        "item_id": _s(i.get("item_id"), 40),
        "name": _s(i.get("name") or i.get("item_name"), 255),
        "sku": _s(i.get("sku"), 120),
        "unit": _s(i.get("unit"), 40),
        "status": _s(i.get("status"), 20),
        "item_type": _s(i.get("item_type"), 40),
        "product_type": _s(i.get("product_type"), 40),
        "brand": _s(i.get("brand"), 120),
        "description": _s(i.get("description"), 1000),
        "rate": _f(i.get("rate")),
        "purchase_rate": _f(i.get("purchase_rate")),
        "tax_id": _s(i.get("tax_id"), 40),
        "tax_name": _s(i.get("tax_name"), 120),
        "tax_percentage": _f(i.get("tax_percentage")),
        "account_id": _s(i.get("account_id"), 40),
        "account_name": _s(i.get("account_name"), 255),
        "purchase_account_id": _s(i.get("purchase_account_id"), 40),
        "purchase_account_name": _s(i.get("purchase_account_name"), 255),
        "track_inventory": int(bool(i.get("track_inventory"))),
        "can_be_sold": int(bool(i.get("can_be_sold"))),
        "can_be_purchased": int(bool(i.get("can_be_purchased"))),
        "stock_on_hand": _f(i.get("stock_on_hand")),
        "available_stock": _f(i.get("available_stock")),
        "created_time": _dt(i.get("created_time")),
        "last_modified_time": _dt(i.get("last_modified_time")),
        "raw_json": json.dumps(i, separators=(",", ":")),
    }


def fetch_items(max_pages: int) -> list[dict[str, Any]]:
    from common.zoho_client import ZohoClient

    client = ZohoClient()
    items: list[dict[str, Any]] = []
    for page in range(1, max_pages + 1):
        body = client.get("/items", {"per_page": 200, "page": page, "filter_by": "Status.All"})
        batch = list(body.get("items") or [])
        items += batch
        print(f"  page {page}: {len(batch)} items")
        if not (body.get("page_context") or {}).get("has_more_page"):
            break
    else:
        print(f"  stopped at --max-pages {max_pages}; more pages remain", file=sys.stderr)
    return items


def save(rows: list[dict[str, Any]]) -> int:
    cols = ", ".join(COLUMNS)
    marks = ", ".join(["%s"] * len(COLUMNS))
    updates = ", ".join(f"{c}=VALUES({c})" for c in COLUMNS if c != "item_id")
    with db.connect() as conn, conn.cursor() as cur:
        cur.execute(DDL)
        cur.executemany(
            f"INSERT INTO {TABLE} ({cols}) VALUES ({marks}) ON DUPLICATE KEY UPDATE {updates}",
            [tuple(r[c] for c in COLUMNS) for r in rows],
        )
    return len(rows)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--from-json", type=Path, help="Load a saved /items response ({'items': [...]}) instead of calling Zoho")
    p.add_argument("--max-pages", type=int, default=50, help="Safety cap, 200 items per page (default 50)")
    p.add_argument("--dry-run", action="store_true", help="Build rows but don't write to the DB")
    args = p.parse_args()

    if args.from_json:
        items = list(json.loads(args.from_json.read_text(encoding="utf-8")).get("items") or [])
    else:
        print("Fetching items from Zoho…")
        items = fetch_items(args.max_pages)

    rows = [to_row(i) for i in items if i.get("item_id")]
    if not rows:
        print("No items; nothing saved.", file=sys.stderr)
        return 1
    if args.dry_run:
        print(f"Dry run: {len(rows)} items built, nothing written")
        return 0
    print(f"Saved {save(rows)} items to {TABLE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
