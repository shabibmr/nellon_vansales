"""Fetch one Zoho Books invoice in full by invoice_id.

Prints the raw Books v3 JSON (code, message, and the invoice object,
including line items) to stdout.

Usage (from reports/mis):
  python zoho_api_tools/fetch_invoice.py INVOICE_ID
  python zoho_api_tools/fetch_invoice.py INVOICE_ID --out invoice.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

MIS_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MIS_ROOT))

from zoho_client import ZohoClient  # noqa: E402


def _invoice_id(value: str) -> str:
    text = value.strip()
    if not text.isdigit():
        raise argparse.ArgumentTypeError("invoice_id must be a numeric Zoho id")
    return text


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fetch one full Zoho Books invoice.")
    parser.add_argument("invoice_id", type=_invoice_id, help="Zoho Books invoice_id")
    parser.add_argument(
        "--out",
        type=Path,
        help="Also write the JSON to this file (UTF-8).",
    )
    args = parser.parse_args(argv)

    client = ZohoClient()
    body = client.get(
        f"/invoices/{args.invoice_id}",
        params={"accept": "json"},
    )
    text = json.dumps(body, indent=2, ensure_ascii=False)
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"fetch_invoice failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
