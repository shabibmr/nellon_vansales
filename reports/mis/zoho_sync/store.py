"""The `Store` protocol and an in-memory implementation for tests.

Plan: docs/sync/transaction-sync-plan.md, "`Store` protocol". Both `MemoryStore`
here and the MariaDB `store_db.Store` implement every method below; the pipeline,
`masters.ensure`, and `watermark.py` only ever see this interface.

Primary-key columns are fixed by the schema in `reports/db.py`, not by a spec, so
they are kept here rather than passed on every call.
"""

from __future__ import annotations

from datetime import date
from typing import Any, Iterable, Protocol, runtime_checkable

# Table -> primary-key column(s), in schema order. `reports/db.py` is the source
# of truth; keep this in sync with it.
TABLE_KEY_COLUMNS: dict[str, tuple[str, ...]] = {
    "customers": ("customer_id",),
    "vendors": ("vendor_id",),
    "items": ("item_id",),
    "item_units": ("item_id", "unit_conversion_id"),
    "accounts": ("account_id",),
    "locations": ("location_id",),
    "salespersons": ("salesperson_id",),
    "sales_invoices": ("invoice_id",),
    "sales_lines": ("line_item_id",),
    "debit_notes": ("debit_note_id",),
    "debit_note_lines": ("line_item_id",),
    "purchase_docs": ("kind", "doc_id"),
    "purchase_lines": ("line_item_id",),
    "sales_orders": ("salesorder_id",),
    "sales_order_lines": ("line_item_id",),
    "vendor_credits": ("vendor_credit_id",),
    "vendor_credit_lines": ("line_item_id",),
    "vendor_payments": ("payment_id",),
    "vendor_payment_bills": ("bill_payment_id",),
}


def key_for(table: str, row: dict[str, Any]) -> Any:
    """The row's primary key: a scalar for a single-column key, else a tuple."""
    cols = TABLE_KEY_COLUMNS.get(table)
    if not cols:
        raise KeyError(f"store: no primary key registered for table {table!r}")
    if len(cols) == 1:
        return row[cols[0]]
    return tuple(row[c] for c in cols)


@runtime_checkable
class Store(Protocol):
    """Everything `masters.ensure`, `pipeline.py`, and `watermark.py` need.

    `key` for `get`/`has` is whatever `key_for` would build: a scalar id, or a
    tuple for a composite key such as `purchase_docs` (`kind`, `doc_id`).
    """

    def get(self, table: str, key: Any) -> dict[str, Any] | None: ...

    def has(self, table: str, key: Any) -> bool: ...

    def upsert(self, table: str, rows: list[dict[str, Any]], update_cols: list[str] | None = None) -> None: ...

    def replace_lines(self, table: str, parent_col: str, parent_id: Any, rows: list[dict[str, Any]]) -> None:
        """Upsert `rows`, then delete that parent's lines not present in `rows`."""
        ...

    def replace_range(self, account_id: str, date_from: date, date_to: date, rows: list[dict[str, Any]]) -> None:
        """Upsert `gl_journals` rows for `account_id` dated in [date_from, date_to], then
        delete that account's rows in the same range that are not in `rows`."""
        ...

    def iter_table(self, table: str) -> Iterable[dict[str, Any]]:
        """Every row of `table`, for `cogs.py`'s own filtering (small tables only:
        `gl_journals`, and a document's own lines table)."""
        ...

    def max_value(self, table: str, column: str) -> Any:
        """The highest value of `column` in `table`, or None if the table is empty."""
        ...

    def add_pending(
        self, dataset: str, doc_id: str, modified_time: str = "", reason: str = "", error: str | None = None
    ) -> None: ...

    def list_pending(self, dataset: str) -> list[dict[str, Any]]: ...

    def clear_pending(self, dataset: str, doc_id: str) -> None: ...

    def get_watermark(self, dataset: str) -> str | None: ...

    def set_watermark(self, dataset: str, watermark: str) -> None: ...


class MemoryStore:
    """A `Store` backed by plain dicts. Tests only — no file or network I/O."""

    def __init__(self) -> None:
        self._tables: dict[str, dict[Any, dict[str, Any]]] = {}
        self._gl_journals: dict[tuple[str, str], dict[str, Any]] = {}
        self._pending: dict[str, dict[str, dict[str, Any]]] = {}
        self._watermarks: dict[str, str] = {}

    # -- plain tables ------------------------------------------------------

    def get(self, table: str, key: Any) -> dict[str, Any] | None:
        row = self._tables.get(table, {}).get(key)
        return dict(row) if row is not None else None

    def has(self, table: str, key: Any) -> bool:
        return key in self._tables.get(table, {})

    def upsert(self, table: str, rows: list[dict[str, Any]], update_cols: list[str] | None = None) -> None:
        bucket = self._tables.setdefault(table, {})
        for row in rows:
            key = key_for(table, row)
            existing = bucket.get(key)
            if existing is None:
                bucket[key] = dict(row)
                continue
            cols = update_cols if update_cols is not None else row.keys()
            merged = dict(existing)
            for col in cols:
                if col in row:
                    merged[col] = row[col]
            bucket[key] = merged

    def replace_lines(self, table: str, parent_col: str, parent_id: Any, rows: list[dict[str, Any]]) -> None:
        self.upsert(table, rows)
        bucket = self._tables.setdefault(table, {})
        keep = {key_for(table, row) for row in rows}
        stale = [
            key
            for key, row in bucket.items()
            if row.get(parent_col) == parent_id and key not in keep
        ]
        for key in stale:
            del bucket[key]

    def replace_range(self, account_id: str, date_from: date, date_to: date, rows: list[dict[str, Any]]) -> None:
        for row in rows:
            key = (row["account_id"], row["categorized_transaction_id"])
            self._gl_journals[key] = dict(row)
        keep = {(row["account_id"], row["categorized_transaction_id"]) for row in rows}
        stale = [
            key
            for key, row in self._gl_journals.items()
            if row["account_id"] == account_id
            and date_from <= row["transaction_date"] <= date_to
            and key not in keep
        ]
        for key in stale:
            del self._gl_journals[key]

    def gl_journal_rows(self) -> list[dict[str, Any]]:
        """Test helper: every stored `gl_journals` row (not part of the `Store` protocol)."""
        return [dict(r) for r in self._gl_journals.values()]

    def iter_table(self, table: str) -> Iterable[dict[str, Any]]:
        if table == "gl_journals":
            return [dict(r) for r in self._gl_journals.values()]
        return [dict(r) for r in self._tables.get(table, {}).values()]

    def max_value(self, table: str, column: str) -> Any:
        rows = self._tables.get(table, {}).values()
        values = [row.get(column) for row in rows if row.get(column) is not None]
        return max(values) if values else None

    # -- sync_pending -------------------------------------------------------

    def add_pending(
        self, dataset: str, doc_id: str, modified_time: str = "", reason: str = "", error: str | None = None
    ) -> None:
        bucket = self._pending.setdefault(dataset, {})
        existing = bucket.get(doc_id)
        attempts = (existing["attempts"] if existing else 0) + 1
        bucket[doc_id] = {
            "dataset": dataset,
            "doc_id": doc_id,
            "modified_time": modified_time,
            "reason": reason,
            "last_error": error,
            "attempts": attempts,
        }

    def list_pending(self, dataset: str) -> list[dict[str, Any]]:
        return [dict(row) for row in self._pending.get(dataset, {}).values()]

    def clear_pending(self, dataset: str, doc_id: str) -> None:
        self._pending.get(dataset, {}).pop(doc_id, None)

    # -- sync_state -----------------------------------------------------------

    def get_watermark(self, dataset: str) -> str | None:
        return self._watermarks.get(dataset)

    def set_watermark(self, dataset: str, watermark: str) -> None:
        self._watermarks[dataset] = watermark
