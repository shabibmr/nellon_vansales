#!/usr/bin/env python3
"""MIS reports from Zoho Books.

Currently:
  trial-balance  — period TB from General Ledger + Chart of Accounts

Usage:
  .venv/bin/python main.py trial-balance --from-date 2026-04-01 --to-date 2026-10-11
  .venv/bin/python main.py trial-balance --from-date 2026-04-01 --to-date 2026-10-11 --include-zero
"""

from __future__ import annotations

import argparse
import json
from datetime import date, datetime
from pathlib import Path

from exporters import write_csv, write_excel_sheets
from reports.trial_balance import COLUMNS, generate_trial_balance
from zoho_client import ZohoClient

OUT_DIR = Path(__file__).resolve().parent / "output"


def _cmd_trial_balance(args: argparse.Namespace) -> int:
    client = ZohoClient()
    rows, summary = generate_trial_balance(
        client,
        args.from_date,
        args.to_date,
        include_zero=args.include_zero,
    )

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"trial_balance_{args.from_date}_{args.to_date}_{stamp}"
    csv_path = OUT_DIR / f"{stem}.csv"
    xlsx_path = OUT_DIR / f"{stem}.xlsx"
    json_path = OUT_DIR / f"{stem}.json"

    write_csv(rows, COLUMNS, csv_path)
    summary_rows = [{"metric": k, "value": v} for k, v in summary.items()]
    write_excel_sheets(
        {
            "TrialBalance": (COLUMNS, rows),
            "Summary": (["metric", "value"], summary_rows),
        },
        xlsx_path,
    )
    json_path.write_text(
        json.dumps({"summary": summary, "rows": rows}, indent=2),
        encoding="utf-8",
    )

    print()
    print(f"Accounts:     {summary['account_count']}")
    print(f"Gross debit:  {summary['debit_total_sum']:,.2f}")
    print(f"Gross credit: {summary['credit_total_sum']:,.2f}")
    print(f"Net debit:    {summary['net_debit_sum']:,.2f}")
    print(f"Net credit:   {summary['net_credit_sum']:,.2f}")
    balanced = abs(summary["debit_total_sum"] - summary["credit_total_sum"]) < 0.015
    print(f"Gross balanced: {balanced}")
    print(f"CSV   -> {csv_path}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Nellon MIS reports from Zoho Books")
    sub = p.add_subparsers(dest="command", required=True)

    tb = sub.add_parser(
        "trial-balance",
        help="Trial balance from /reports/generalledger + /chartofaccounts",
    )
    tb.add_argument("--from-date", required=True, help="YYYY-MM-DD")
    tb.add_argument("--to-date", default=date.today().isoformat(), help="YYYY-MM-DD (default: today)")
    tb.add_argument(
        "--include-zero",
        action="store_true",
        help="Keep accounts with zero debit, credit, and balance",
    )
    tb.set_defaults(func=_cmd_trial_balance)
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
