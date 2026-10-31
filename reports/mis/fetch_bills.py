"""Fetch Zoho Books bills (header + lines) for a date range into MariaDB `bills` / `bill_line_items`.

    GET /bills?date_start=&date_end=&per_page=200&page=N   (list, all statuses)
    GET /bills/{bill_id}                                    (detail, only when not cached / changed)

Details are cached under output/cache/bills/{bill_id}.json (same cache as reports/purchases.py)
and re-fetched only when the list row's `last_modified_time` differs. One header row per bill_id
(upserted); a bill's lines are replaced whole on every load. Full detail kept in `raw_json`.

    python fetch_bills.py --from-date 2026-09-01 --to-date 2026-09-30            # list call + changed details
    python fetch_bills.py --from-date 2026-09-01 --to-date 2026-09-30 --offline  # cache only, no Zoho call
    python fetch_bills.py --from-date 2026-09-01 --to-date 2026-09-30 --dry-run  # no DB write

Detail calls above --max-detail-calls (default 5) abort before fetching, so the count can be approved first.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from reports import db

HERE = Path(__file__).resolve().parent
CACHE = HERE / "output" / "cache" / "bills"

DDL_BILLS = """
CREATE TABLE IF NOT EXISTS bills (
    bill_id            VARCHAR(40)   NOT NULL,
    bill_number        VARCHAR(80)   NOT NULL DEFAULT '',
    reference_number   VARCHAR(120)  NOT NULL DEFAULT '',
    date               DATE          NULL,
    due_date           DATE          NULL,
    status             VARCHAR(30)   NOT NULL DEFAULT '',
    vendor_id          VARCHAR(40)   NOT NULL DEFAULT '',
    vendor_name        VARCHAR(255)  NOT NULL DEFAULT '',
    location_name      VARCHAR(255)  NOT NULL DEFAULT '',
    currency_code      VARCHAR(10)   NOT NULL DEFAULT '',
    exchange_rate      DECIMAL(18,6) NOT NULL DEFAULT 1,
    sub_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
    tax_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
    total              DECIMAL(18,2) NOT NULL DEFAULT 0,
    balance            DECIMAL(18,2) NOT NULL DEFAULT 0,
    line_count         INT UNSIGNED  NOT NULL DEFAULT 0,
    created_time       DATETIME      NULL,
    last_modified_time DATETIME      NULL,
    raw_json           LONGTEXT      NULL,
    fetched_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (bill_id),
    KEY idx_date (date),
    KEY idx_number (bill_number),
    KEY idx_created (created_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
"""

DDL_LINES = """
CREATE TABLE IF NOT EXISTS bill_line_items (
    bill_id         VARCHAR(40)   NOT NULL,
    line_item_id    VARCHAR(40)   NOT NULL,
    line_no         INT UNSIGNED  NOT NULL,
    date            DATE          NULL,
    bill_number     VARCHAR(80)   NOT NULL DEFAULT '',
    item_id         VARCHAR(40)   NOT NULL DEFAULT '',
    name            VARCHAR(255)  NOT NULL DEFAULT '',
    sku             VARCHAR(120)  NOT NULL DEFAULT '',
    description     VARCHAR(1000) NOT NULL DEFAULT '',
    item_type       VARCHAR(40)   NOT NULL DEFAULT '',
    account_id      VARCHAR(40)   NOT NULL DEFAULT '',
    account_name    VARCHAR(255)  NOT NULL DEFAULT '',
    location_name   VARCHAR(255)  NOT NULL DEFAULT '',
    unit            VARCHAR(40)   NOT NULL DEFAULT '',
    quantity        DECIMAL(18,4) NOT NULL DEFAULT 0,
    rate            DECIMAL(18,6) NOT NULL DEFAULT 0,
    discount        DECIMAL(18,4) NOT NULL DEFAULT 0,
    tax_percentage  DECIMAL(9,4)  NOT NULL DEFAULT 0,
    item_total      DECIMAL(18,2) NOT NULL DEFAULT 0,
    base_amount     DECIMAL(18,2) NOT NULL DEFAULT 0,
    raw_json        LONGTEXT      NULL,
    PRIMARY KEY (bill_id, line_item_id),
    KEY idx_item (item_id),
    KEY idx_date (date),
    KEY idx_account (account_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
"""

BILL_COLUMNS = [
    "bill_id", "bill_number", "reference_number", "date", "due_date", "status", "vendor_id", "vendor_name",
    "location_name", "currency_code", "exchange_rate", "sub_total", "tax_total", "total", "balance",
    "line_count", "created_time", "last_modified_time", "raw_json",
]
LINE_COLUMNS = [
    "bill_id", "line_item_id", "line_no", "date", "bill_number", "item_id", "name", "sku", "description",
    "item_type", "account_id", "account_name", "location_name", "unit", "quantity", "rate", "discount",
    "tax_percentage", "item_total", "base_amount", "raw_json",
]


def _f(val: Any) -> float:
    try:
        return float(val or 0)
    except (TypeError, ValueError):
        return 0.0


def _s(val: Any, limit: int) -> str:
    return str(val if val is not None else "")[:limit]


def _d(val: Any) -> str | None:
    text = str(val or "")[:10]
    return text if len(text) == 10 and text[4] == "-" else None


def _dt(val: Any) -> str | None:
    # Zoho: 2026-04-01T12:32:26+0400 -> keep the local wall-clock part.
    return str(val)[:19].replace("T", " ") if val else None


def bill_row(b: dict[str, Any]) -> dict[str, Any]:
    return {
        "bill_id": _s(b.get("bill_id"), 40),
        "bill_number": _s(b.get("bill_number"), 80),
        "reference_number": _s(b.get("reference_number"), 120),
        "date": _d(b.get("date")),
        "due_date": _d(b.get("due_date")),
        "status": _s(b.get("status"), 30),
        "vendor_id": _s(b.get("vendor_id"), 40),
        "vendor_name": _s(b.get("vendor_name"), 255),
        "location_name": _s(b.get("location_name"), 255),
        "currency_code": _s(b.get("currency_code"), 10),
        "exchange_rate": _f(b.get("exchange_rate")) or 1.0,
        "sub_total": _f(b.get("sub_total")),
        "tax_total": _f(b.get("tax_total")),
        "total": _f(b.get("total")),
        "balance": _f(b.get("balance")),
        "line_count": len(b.get("line_items") or []),
        "created_time": _dt(b.get("created_time")),
        "last_modified_time": _dt(b.get("last_modified_time")),
        "raw_json": json.dumps(b, separators=(",", ":")),
    }


def line_rows(b: dict[str, Any]) -> list[dict[str, Any]]:
    fx = _f(b.get("exchange_rate")) or 1.0
    out = []
    for n, ln in enumerate(b.get("line_items") or [], 1):
        out.append({
            "bill_id": _s(b.get("bill_id"), 40),
            "line_item_id": _s(ln.get("line_item_id") or n, 40),
            "line_no": n,
            "date": _d(b.get("date")),
            "bill_number": _s(b.get("bill_number"), 80),
            "item_id": _s(ln.get("item_id"), 40),
            "name": _s(ln.get("name"), 255),
            "sku": _s(ln.get("sku"), 120),
            "description": _s(ln.get("description"), 1000),
            "item_type": _s(ln.get("item_type") or ln.get("product_type"), 40),
            "account_id": _s(ln.get("account_id"), 40),
            "account_name": _s(ln.get("account_name"), 255),
            "location_name": _s(ln.get("location_name") or b.get("location_name"), 255),
            "unit": _s(ln.get("unit"), 40),
            "quantity": _f(ln.get("quantity")),
            "rate": _f(ln.get("rate")),
            "discount": _f(ln.get("discount")),
            "tax_percentage": _f(ln.get("tax_percentage")),
            "item_total": _f(ln.get("item_total")),
            "base_amount": round(_f(ln.get("item_total")) * fx, 2),
            "raw_json": json.dumps(ln, separators=(",", ":")),
        })
    return out


def _read(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _write(path: Path, data: dict) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    tmp.replace(path)


def cached_bills(from_date: str, to_date: str) -> list[dict[str, Any]]:
    docs = [_read(p) for p in sorted(CACHE.glob("*.json"))]
    return [d for d in docs if d and from_date <= str(d.get("date", "")) <= to_date]


def fetch_bills(from_date: str, to_date: str, max_detail_calls: int) -> list[dict[str, Any]] | None:
    from zoho_client import ZohoClient

    client = ZohoClient()
    listed, page = [], 1
    while True:
        body = client.get("/bills", {"date_start": from_date, "date_end": to_date, "per_page": 200, "page": page})
        listed += body.get("bills") or []
        if not (body.get("page_context") or {}).get("has_more_page"):
            break
        page += 1
    print(f"  list: {len(listed)} bills in range ({page} list call(s))")

    CACHE.mkdir(parents=True, exist_ok=True)
    stale = [h for h in listed
             if (_read(CACHE / f"{h['bill_id']}.json") or {}).get("last_modified_time") != h.get("last_modified_time")]
    print(f"  details: {len(listed) - len(stale)} cached & unchanged, {len(stale)} new/changed")
    for h in stale:
        print(f"    {h.get('bill_number')} date={h.get('date')} last_modified={h.get('last_modified_time')}")
    if len(stale) > max_detail_calls:
        print(f"  {len(stale)} detail calls exceed --max-detail-calls {max_detail_calls}; aborted, nothing written",
              file=sys.stderr)
        return None
    for h in stale:
        detail = client.get(f"/bills/{h['bill_id']}").get("bill") or {}
        _write(CACHE / f"{h['bill_id']}.json", detail)

    listed_ids = {h["bill_id"] for h in listed}
    gone = [d.get("bill_number") for d in cached_bills(from_date, to_date) if d.get("bill_id") not in listed_ids]
    if gone:
        print(f"  cached but no longer listed by Zoho (deleted / re-dated), not loaded: {gone}")
    return [_read(CACHE / f"{bid}.json") for bid in sorted(listed_ids)]


def save(bills: list[dict[str, Any]]) -> tuple[int, int]:
    heads = [bill_row(b) for b in bills]
    lines = [r for b in bills for r in line_rows(b)]
    bcols, lcols = ", ".join(BILL_COLUMNS), ", ".join(LINE_COLUMNS)
    updates = ", ".join(f"{c}=VALUES({c})" for c in BILL_COLUMNS if c != "bill_id")
    ids = [h["bill_id"] for h in heads]
    with db.connect() as conn, conn.cursor() as cur:
        cur.execute(DDL_BILLS)
        cur.execute(DDL_LINES)
        cur.executemany(
            f"INSERT INTO bills ({bcols}) VALUES ({', '.join(['%s'] * len(BILL_COLUMNS))}) "
            f"ON DUPLICATE KEY UPDATE {updates}",
            [tuple(h[c] for c in BILL_COLUMNS) for h in heads],
        )
        for i in range(0, len(ids), 500):
            chunk = ids[i:i + 500]
            cur.execute(f"DELETE FROM bill_line_items WHERE bill_id IN ({', '.join(['%s'] * len(chunk))})", chunk)
        cur.executemany(
            f"INSERT INTO bill_line_items ({lcols}) VALUES ({', '.join(['%s'] * len(LINE_COLUMNS))})",
            [tuple(r[c] for c in LINE_COLUMNS) for r in lines],
        )
    return len(heads), len(lines)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--from-date", required=True)
    p.add_argument("--to-date", required=True)
    p.add_argument("--offline", action="store_true", help="Load from output/cache/bills only, no Zoho call")
    p.add_argument("--max-detail-calls", type=int, default=5, help="Abort if more bill details need fetching")
    p.add_argument("--dry-run", action="store_true", help="Build rows but don't write to the DB")
    args = p.parse_args()

    if args.offline:
        bills = cached_bills(args.from_date, args.to_date)
    else:
        print("Fetching bills from Zoho…")
        bills = fetch_bills(args.from_date, args.to_date, args.max_detail_calls)
        if bills is None:
            return 2
    bills = [b for b in bills if b and b.get("bill_id")]
    if not bills:
        print("No bills; nothing saved.", file=sys.stderr)
        return 1
    if args.dry_run:
        print(f"Dry run: {len(bills)} bills, {sum(len(line_rows(b)) for b in bills)} lines built, nothing written")
        return 0
    n_b, n_l = save(bills)
    print(f"Saved {n_b} bills to bills, {n_l} lines to bill_line_items")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
