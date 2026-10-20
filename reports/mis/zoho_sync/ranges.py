"""Cost of Sales date ranges: pure logic, no I/O.

Plan: docs/sync/transaction-sync-plan.md, "Step 3 — Cost of Sales pass" /
"Which dates". Task 7, bullet 1.

Dates come from, merged into continuous ranges:
- Every date of a posted, draft, or void invoice this run stored (not debit
  notes: debit-note COGS does not use postings — task 0 finding 2).
- On the 02:00 run: the trailing window (current month, plus the previous
  month through its 5th day).
- On the 02:00 run: for every bill this run changed with date D, every date
  from D to today.
- Every date range already in `sync_pending` with `dataset='cogs'`
  (`doc_id` formatted `YYYY-MM-DD..YYYY-MM-DD`).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta


@dataclass(frozen=True)
class DateRange:
    date_from: date
    date_to: date


def is_02_run(hour: int) -> bool:
    """True when the run's clock hour is 2 (the nightly 02:00 run)."""
    return hour == 2


def trailing_window(today: date) -> DateRange:
    """Current month, plus the previous month through its 5th day."""
    start_of_this_month = today.replace(day=1)
    last_day_prev_month = start_of_this_month - timedelta(days=1)
    start_of_prev_month = last_day_prev_month.replace(day=1)
    window_start = min(start_of_prev_month.replace(day=5), last_day_prev_month)
    return DateRange(window_start, today)


def parse_pending_doc_id(doc_id: str) -> DateRange:
    """`YYYY-MM-DD..YYYY-MM-DD` -> `DateRange`."""
    start_text, end_text = doc_id.split("..")
    return DateRange(date.fromisoformat(start_text), date.fromisoformat(end_text))


def format_range_doc_id(date_range: DateRange) -> str:
    return f"{date_range.date_from.isoformat()}..{date_range.date_to.isoformat()}"


def merge_ranges(ranges: list[DateRange]) -> list[DateRange]:
    """Merge overlapping or adjacent ranges into the fewest continuous ones."""
    if not ranges:
        return []
    ordered = sorted(ranges, key=lambda r: (r.date_from, r.date_to))
    merged = [ordered[0]]
    for current in ordered[1:]:
        last = merged[-1]
        if current.date_from <= last.date_to + timedelta(days=1):
            if current.date_to > last.date_to:
                merged[-1] = DateRange(last.date_from, current.date_to)
        else:
            merged.append(current)
    return merged


def cost_of_sales_ranges(
    invoice_dates: list[date],
    today: date,
    hour: int,
    changed_bill_dates: list[date],
    pending_doc_ids: list[str],
) -> list[DateRange]:
    """Build the merged Cost-of-Sales date ranges for this run.

    `invoice_dates` are dates of posted/draft/void invoices this run stored
    (debit notes excluded). `changed_bill_dates` are the dates of bills this
    run changed; only used on the 02:00 run, each expanded to `D..today`.
    `pending_doc_ids` are `sync_pending` rows with `dataset='cogs'`.
    """
    single_dates = set(invoice_dates)
    ranges = [DateRange(d, d) for d in single_dates]

    if is_02_run(hour):
        ranges.append(trailing_window(today))
        for bill_date in changed_bill_dates:
            ranges.append(DateRange(bill_date, today))

    for doc_id in pending_doc_ids:
        ranges.append(parse_pending_doc_id(doc_id))

    return merge_ranges(ranges)
