"""Ledger postings from Zoho Books → MariaDB, shared by the fetch_* scripts.

    GET /chartofaccounts/transactions?account_id=…&per_page=200&page=N
        [&date.start=YYYY-MM-DD&date.end=YYYY-MM-DD][&transaction_type=…]

One row per posting (Zoho's `categorized_transaction_id`), so re-running over
an overlapping range updates rows instead of duplicating them. Each script
fixes its own account(s) and table; `check_account` refuses anything else.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Callable

from reports import db

Pages = list[tuple[list[dict[str, Any]], dict[str, Any]]]


def ddl(table: str) -> str:
    return f"""
    CREATE TABLE IF NOT EXISTS {table} (
        account_id                 VARCHAR(40)   NOT NULL,
        categorized_transaction_id VARCHAR(40)   NOT NULL,
        account_name               VARCHAR(255)  NOT NULL DEFAULT '',
        account_code               VARCHAR(40)   NOT NULL DEFAULT '',
        transaction_id             VARCHAR(40)   NOT NULL DEFAULT '',
        transaction_type           VARCHAR(60)   NOT NULL DEFAULT '',
        transaction_type_formatted VARCHAR(120)  NOT NULL DEFAULT '',
        transaction_date           DATE          NULL,
        entry_number               VARCHAR(80)   NOT NULL DEFAULT '',
        reference_number           VARCHAR(120)  NOT NULL DEFAULT '',
        customer_id                VARCHAR(40)   NOT NULL DEFAULT '',
        payee                      VARCHAR(255)  NOT NULL DEFAULT '',
        description                VARCHAR(1000) NOT NULL DEFAULT '',
        debit_or_credit            VARCHAR(10)   NOT NULL DEFAULT '',
        debit_amount               DECIMAL(18,2) NOT NULL DEFAULT 0,
        credit_amount              DECIMAL(18,2) NOT NULL DEFAULT 0,
        amount                     DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT 'debit - credit (Dr +, Cr -)',
        fcy_debit_amount           DECIMAL(18,2) NOT NULL DEFAULT 0,
        fcy_credit_amount          DECIMAL(18,2) NOT NULL DEFAULT 0,
        currency_id                VARCHAR(40)   NOT NULL DEFAULT '',
        currency_code              VARCHAR(10)   NOT NULL DEFAULT '',
        offset_account_name        VARCHAR(255)  NOT NULL DEFAULT '',
        raw_json                   LONGTEXT      NULL,
        fetched_at                 DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (account_id, categorized_transaction_id),
        KEY idx_txn (transaction_id),
        KEY idx_date (transaction_date),
        KEY idx_type_date (transaction_type, transaction_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """


COLUMNS = [
    "account_id", "categorized_transaction_id", "account_name", "account_code",
    "transaction_id", "transaction_type", "transaction_type_formatted", "transaction_date",
    "entry_number", "reference_number", "customer_id", "payee", "description",
    "debit_or_credit", "debit_amount", "credit_amount", "amount",
    "fcy_debit_amount", "fcy_credit_amount", "currency_id", "currency_code",
    "offset_account_name", "raw_json",
]


def _f(val: Any) -> float:
    # Zoho sends "" for the empty side of a posting.
    try:
        return round(float(val or 0), 2)
    except (TypeError, ValueError):
        return 0.0


def _s(val: Any, limit: int) -> str:
    return str(val if val is not None else "")[:limit]


def to_row(t: dict[str, Any], page_context: dict[str, Any]) -> dict[str, Any]:
    debit, credit = _f(t.get("debit_amount")), _f(t.get("credit_amount"))
    return {
        "account_id": _s(t.get("account_id"), 40),
        "categorized_transaction_id": _s(t.get("categorized_transaction_id"), 40),
        "account_name": _s(page_context.get("account_name"), 255),
        "account_code": _s(page_context.get("account_code"), 40),
        "transaction_id": _s(t.get("transaction_id"), 40),
        "transaction_type": _s(t.get("transaction_type"), 60),
        "transaction_type_formatted": _s(t.get("transaction_type_formatted"), 120),
        "transaction_date": t.get("transaction_date") or None,
        "entry_number": _s(t.get("entry_number"), 80),
        "reference_number": _s(t.get("reference_number"), 120),
        "customer_id": _s(t.get("customer_id"), 40),
        "payee": _s(t.get("payee"), 255),
        "description": _s(t.get("description"), 1000),
        "debit_or_credit": _s(t.get("debit_or_credit"), 10),
        "debit_amount": debit,
        "credit_amount": credit,
        "amount": round(debit - credit, 2),
        "fcy_debit_amount": _f(t.get("fcy_debit_amount")),
        "fcy_credit_amount": _f(t.get("fcy_credit_amount")),
        "currency_id": _s(t.get("currency_id"), 40),
        "currency_code": _s(t.get("currency_code"), 10),
        "offset_account_name": _s(t.get("offset_account_name"), 255),
        "raw_json": json.dumps(t, separators=(",", ":")),
    }


def check_account(pages: Pages, accounts: dict[str, str]) -> None:
    """Refuse pages that aren't for `accounts` ({account_id: account_code})."""
    codes = set(accounts.values())
    for txns, ctx in pages:
        code = str(ctx.get("account_code") or "")
        if code and code not in codes:
            raise SystemExit(f"Response is for account code {code!r}, expected {sorted(codes)}; nothing saved.")
        other = {str(t.get("account_id")) for t in txns} - set(accounts)
        if other:
            raise SystemExit(f"Postings for other account_id(s) {sorted(other)}; nothing saved.")


def fetch_pages(
    account_id: str,
    *,
    from_date: str | None,
    to_date: str | None,
    transaction_type: str | None,
    max_pages: int,
) -> Pages:
    """Page through Zoho for one account; returns [(transactions, page_context), ...]."""
    from zoho_client import ZohoClient

    client = ZohoClient()
    params: dict[str, Any] = {"account_id": account_id, "per_page": 200}
    if from_date:
        params["date.start"] = from_date
    if to_date:
        params["date.end"] = to_date
    if transaction_type:
        params["transaction_type"] = transaction_type

    pages: Pages = []
    for page in range(1, max_pages + 1):
        body = client.get("/chartofaccounts/transactions", {**params, "page": page})
        txns = list(body.get("transactions") or [])
        ctx = body.get("page_context") or {}
        pages.append((txns, ctx))
        print(f"  page {page}: {len(txns)} postings")
        if not ctx.get("has_more_page"):
            break
    else:
        print(f"  stopped at --max-pages {max_pages}; more pages remain", file=sys.stderr)
    return pages


def save(table: str, rows: list[dict[str, Any]]) -> int:
    cols = ", ".join(COLUMNS)
    marks = ", ".join(["%s"] * len(COLUMNS))
    updates = ", ".join(
        f"{c}=VALUES({c})" for c in COLUMNS if c not in ("account_id", "categorized_transaction_id")
    )
    with db.connect() as conn, conn.cursor() as cur:
        cur.execute(ddl(table))
        cur.executemany(
            f"INSERT INTO {table} ({cols}) VALUES ({marks}) ON DUPLICATE KEY UPDATE {updates}",
            [tuple(r[c] for c in COLUMNS) for r in rows],
        )
    return len(rows)


def run_cli(
    *,
    accounts: dict[str, str],
    table: str,
    description: str,
    after_save: Callable[[], None] | None = None,
) -> int:
    """Shared CLI: fetch every account in `accounts` (or load --from-json files), check, save."""
    p = argparse.ArgumentParser(description=description, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--from-json", type=Path, action="append",
                   help="Load a saved /chartofaccounts/transactions response instead (repeatable)")
    p.add_argument("--from-date", help="YYYY-MM-DD (date.start)")
    p.add_argument("--to-date", help="YYYY-MM-DD (date.end)")
    p.add_argument("--transaction-type", help="e.g. inventory_valuation_for_invoice (default: all types)")
    p.add_argument("--max-pages", type=int, default=50,
                   help="Safety cap per account, 200 postings per page (default 50)")
    args = p.parse_args()

    pages: Pages = []
    if args.from_json:
        for path in args.from_json:
            body = json.loads(path.read_text(encoding="utf-8"))
            pages.append((list(body.get("transactions") or []), body.get("page_context") or {}))
    else:
        for account_id, code in accounts.items():
            print(f"Fetching {code} ({account_id}) postings…")
            pages += fetch_pages(
                account_id,
                from_date=args.from_date,
                to_date=args.to_date,
                transaction_type=args.transaction_type,
                max_pages=args.max_pages,
            )

    check_account(pages, accounts)
    rows = [to_row(t, ctx) for txns, ctx in pages for t in txns]
    if not rows:
        print("No postings returned; nothing saved.")
        return 0
    n = save(table, rows)
    print(f"Saved {n} postings to {table}")
    for account_id, code in accounts.items():
        mine = [r for r in rows if r["account_id"] == account_id]
        if mine:
            print(f"  {code}: {len(mine)} postings, Dr {sum(r['debit_amount'] for r in mine):,.2f}, "
                  f"Cr {sum(r['credit_amount'] for r in mine):,.2f}")
    if after_save:
        after_save()
    return 0
