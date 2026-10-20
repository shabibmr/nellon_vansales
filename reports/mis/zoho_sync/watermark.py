"""Read and write `sync_state` watermarks through the `Store`.

Plan: docs/sync/transaction-sync-plan.md, "Watermarks". The watermark is the
raw Zoho `last_modified_time` text, stored and passed verbatim except for
percent-encoding `+` as `%2B` on the outgoing request. Never add a second:
"at or after" vs "after" is the list's own job (`specs.py`), not this module's.
"""

from __future__ import annotations

from .store import Store


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


def encode_watermark(watermark: str) -> str:
    """Percent-encode for the outgoing query string. `+` -> `%2B`; nothing else
    needs it (the offset digits and `:`/`T` are left as-is, matching the
    invoices spec's own `%2B0800` example)."""
    return watermark.replace("+", "%2B")


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
            store.set_watermark(dataset, value)
        seeded[dataset] = value
    return seeded
