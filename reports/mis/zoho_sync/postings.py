"""Pull Cost of Sales postings for date ranges, through a `Run`.

Plan: docs/sync/transaction-sync-plan.md, "Step 3 — Cost of Sales pass", "The
call". `account_postings.fetch_pages` does the paging against the run's
gateway; this module strips `raw_json` (the run folder's page file is the raw
copy — plan, "The call") and replaces each range in `gl_journals` through
`store.replace_range`. A range whose pull fails is left alone and recorded in
`sync_pending` with `dataset='cogs'`, so the next run retries it (`ranges.py`
reads it back via `pending_doc_ids`).
"""

from __future__ import annotations

from typing import Any

from reports.account_postings import fetch_pages, to_row
from seed_common import parse_date

from .ranges import DateRange, format_range_doc_id

COS_ACCOUNT_ID = "3331482000000034003"
_MAX_PAGES = 50


def pull_range(run: Any, account_id: str, date_range: DateRange) -> bool:
    """Pull every page for `date_range` and replace it in `gl_journals`.

    Returns True on success. On failure, leaves `gl_journals` as it was,
    records the range in `sync_pending`, and returns False.
    """
    doc_id = format_range_doc_id(date_range)
    try:
        pages = fetch_pages(
            account_id,
            from_date=date_range.date_from.isoformat(),
            to_date=date_range.date_to.isoformat(),
            transaction_type=None,
            max_pages=_MAX_PAGES,
            gateway=run.gateway,
        )
    except Exception as exc:  # noqa: BLE001 - any failure defers this range, never raises
        run.store.add_pending("cogs", doc_id, reason="postings pull failed", error=str(exc))
        return False

    rows: list[dict[str, Any]] = []
    for transactions, page_context in pages:
        for transaction in transactions:
            row = to_row(transaction, page_context)
            row["raw_json"] = None
            # `to_row`'s transaction_date is the Zoho string; `replace_range`
            # (and the `DATE` column) need a `date`.
            row["transaction_date"] = parse_date(row["transaction_date"])
            rows.append(row)

    run.store.replace_range(account_id, date_range.date_from, date_range.date_to, rows)
    run.store.clear_pending("cogs", doc_id)
    return True


def pull_ranges(run: Any, account_id: str, date_ranges: list[DateRange]) -> list[DateRange]:
    """Pull every range; returns the ones that succeeded (failures stay pending)."""
    return [date_range for date_range in date_ranges if pull_range(run, account_id, date_range)]
