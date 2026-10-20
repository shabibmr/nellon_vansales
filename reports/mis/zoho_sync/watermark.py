"""Read and write `sync_state` watermarks through the `Store`.

Plan: docs/sync/transaction-sync-plan.md, "Watermarks". The watermark is the
raw Zoho `last_modified_time` text, stored and passed verbatim.
`requests` encodes `+` as `%2B` on the outgoing query string. Never add a second:
"at or after" vs "after" is the list's own job (`specs.py`), not this module's.
"""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from .store import Store

DUBAI = ZoneInfo("Asia/Dubai")


class NoWatermark(Exception):
    """Raised when a dataset has no seeded watermark. The run refuses to list
    that dataset rather than start from the beginning."""


def get_watermark(store: Store, dataset: str) -> str:
    """The stored watermark, required. Raises `NoWatermark` when there is none."""
    value = store.get_watermark(dataset)
    if not value:
        raise NoWatermark(f"watermark: no sync_state row for dataset {dataset!r}; run seed-watermarks first")
    return value


def set_watermark(store: Store, dataset: str, watermark: str) -> None:
    store.set_watermark(dataset, watermark)


def _parse_wm(text: str) -> datetime:
    s = text.strip().replace(" ", "T")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=DUBAI)
    return dt


def to_zoho_watermark(dt: datetime | str) -> str:
    """Format `dt` as `YYYY-MM-DDTHH:MM:SS+0400` in Asia/Dubai."""
    if isinstance(dt, str):
        parsed = _parse_wm(dt)
    elif dt.tzinfo is None:
        parsed = dt.replace(tzinfo=DUBAI)
    else:
        parsed = dt.astimezone(DUBAI)
    return parsed.strftime("%Y-%m-%dT%H:%M:%S%z")


def highest(current: str, candidate: str) -> str:
    """Return whichever watermark represents the later point in time.

    Compares parsed datetimes, not strings, so mixed timezone offsets order
    correctly. Preserves the exact text of the winning watermark.
    """
    if not current:
        return candidate
    if not candidate:
        return current
    try:
        if _parse_wm(candidate) > _parse_wm(current):
            return candidate
        return current
    except Exception:
        return candidate if candidate > current else current


def seed(store: Store, header_tables: dict[str, str]) -> dict[str, str | None]:
    """First-run seed: set each dataset's watermark to the highest
    `last_modified_time` already stored in that dataset's header table.

    `header_tables` maps dataset -> header table name, e.g.
    `{"invoices": "sales_invoices", "debit_notes": "debit_notes", ...}`.
    A dataset whose table is empty gets no watermark (still `NoWatermark` on
    the next list) rather than a guessed value.
    """
    seeded: dict[str, str | None] = {}
    for dataset, table in header_tables.items():
        value = store.max_value(table, "last_modified_time")
        if value:
            wm_text = to_zoho_watermark(value)
            store.set_watermark(dataset, wm_text)
            seeded[dataset] = wm_text
        else:
            seeded[dataset] = None
    return seeded
