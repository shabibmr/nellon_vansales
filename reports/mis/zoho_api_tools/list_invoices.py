"""List Zoho Books invoices whose invoice date falls in a range.

Follows GET /invoices pages (200 per page) and prints one JSON object:
code, message, date_start, date_end, invoice_count, and invoices.
Each row is the list summary. It does not include full line items.

Usage (from reports/mis):
  python zoho_api_tools/list_invoices.py --from 2026-10-01 --to 2026-10-13
  python zoho_api_tools/list_invoices.py --from 2026-10-01 --to 2026-10-13 --out invoices.json
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

MIS_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MIS_ROOT))

from zoho_client import ZohoClient  # noqa: E402

PER_PAGE = 200
MAX_PAGES = 100


def _date(value: str) -> str:
    text = value.strip()
    try:
        datetime.strptime(text, "%Y-%m-%d")
    except ValueError as exc:
        raise argparse.ArgumentTypeError("use YYYY-MM-DD") from exc
    return text


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="List Zoho Books invoices in a date range.")
    parser.add_argument("--from", dest="date_start", type=_date, required=True, help="Invoice date start, inclusive")
    parser.add_argument("--to", dest="date_end", type=_date, required=True, help="Invoice date end, inclusive")
    parser.add_argument("--out", type=Path, help="Also write the JSON to this file (UTF-8).")
    args = parser.parse_args(argv)
    if args.date_start > args.date_end:
        parser.error("--from must be on or before --to")

    client = ZohoClient()
    invoices: list[dict] = []
    page = 1
    while True:
        body = client.get(
            "/invoices",
            params={
                "date_start": args.date_start,
                "date_end": args.date_end,
                "sort_column": "date",
                "page": page,
                "per_page": PER_PAGE,
            },
        )
        invoices.extend(body.get("invoices") or [])
        context = body.get("page_context") or {}
        if not context.get("has_more_page"):
            break
        page += 1
        if page > MAX_PAGES:
            raise RuntimeError(f"stopped after {MAX_PAGES} pages ({PER_PAGE} invoices each)")

    result = {
        "code": 0,
        "message": "success",
        "date_start": args.date_start,
        "date_end": args.date_end,
        "page_count": page,
        "invoice_count": len(invoices),
        "invoices": invoices,
    }
    text = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"list_invoices failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
