"""Cost of Sales helpers: load invoice postings and apply header/line COGS.

Plan: docs/sync/transaction-sync-plan.md, "Step 3 — Cost of Sales pass",
"What is written". `write_invoice_cogs` and `write_debit_note_cogs` are the
wiring task 7 asks for: read a document's own lines through `store.iter_table`,
call the pure `apply_cogs`, and write header/line COGS plus `cogs_synced_at`
back through `store.upsert`.
"""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Any, Iterable, Protocol

from seed_common import cents, d, prorate

COS_ACCOUNT_ID = "3331482000000034003"
_INVOICE_VALUATION = "inventory_valuation_for_invoice"


class PostingsStore(Protocol):
    def iter_table(self, table: str) -> Iterable[dict[str, Any]]:
        ...

    def upsert(self, table: str, rows: list[dict[str, Any]], update_cols: list[str] | None = None) -> None:
        ...


def load_invoice_postings(
    store: PostingsStore,
    account_id: str,
    invoice_ids: Iterable[str],
) -> dict[str, Decimal]:
    """Sum inventory_valuation_for_invoice amounts for the given invoice ids on account_id."""
    wanted = {str(i) for i in invoice_ids}
    if not wanted:
        return {}
    totals: dict[str, Decimal] = {}
    for row in store.iter_table("gl_journals"):
        if str(row.get("account_id") or "") != str(account_id):
            continue
        if row.get("transaction_type") != _INVOICE_VALUATION:
            continue
        tid = str(row.get("transaction_id") or "")
        if tid not in wanted:
            continue
        totals[tid] = totals.get(tid, Decimal("0")) + cents(d(row.get("amount")))
    return {k: cents(v) for k, v in totals.items()}


def apply_cogs(
    status: str,
    lines: list[dict[str, Any]],
    postings_total: Decimal | None,
) -> tuple[Decimal, list[Decimal]]:
    """Return (header_cogs, per-line cogs) for the Cost of Sales cases.

    Draft/void → 0. No postings → each line's own cost (baseline_cogs). Postings
    found → header is that total, spread by baseline_cogs (or net_sales if those
    sum to 0) via seed_common.prorate.
    """
    n = len(lines)
    if (status or "").lower() in ("draft", "void"):
        return Decimal("0.00"), [Decimal("0.00")] * n

    baseline = [cents(d(ln.get("baseline_cogs", ln.get("cogs")))) for ln in lines]
    if postings_total is None:
        header = cents(sum(baseline, Decimal("0")))
        return header, list(baseline)

    header = cents(d(postings_total))
    if n == 0:
        return header, []
    if n == 1:
        return header, [header]

    weights = baseline
    if sum(weights) <= 0:
        weights = [d(ln.get("net_sales")) for ln in lines]
    return header, prorate(header, weights)


def _group_by(store: PostingsStore, table: str, parent_col: str) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in store.iter_table(table):
        grouped.setdefault(row.get(parent_col), []).append(row)
    return grouped


def write_invoice_cogs(
    store: PostingsStore,
    account_id: str,
    invoices: Iterable[dict[str, Any]],
    now: datetime,
) -> None:
    """For each invoice row (`invoice_id`, `status`) dated in a range this run
    pulled, apply header/line COGS per the plan's table and write them through
    `store`. `invoices` with no matching posting fall to the lines' own cost;
    `apply_cogs` zeroes draft/void regardless. `now` becomes `cogs_synced_at`."""
    rows = list(invoices)
    if not rows:
        return
    postings = load_invoice_postings(store, account_id, (row["invoice_id"] for row in rows))
    lines_by_invoice = _group_by(store, "sales_lines", "invoice_id")

    for row in rows:
        invoice_id = row["invoice_id"]
        lines = lines_by_invoice.get(invoice_id, [])
        header, line_cogs = apply_cogs(row.get("status", ""), lines, postings.get(invoice_id))
        store.upsert(
            "sales_invoices",
            [{"invoice_id": invoice_id, "cogs": header, "cogs_synced_at": now}],
            update_cols=["cogs", "cogs_synced_at"],
        )
        if lines:
            store.upsert(
                "sales_lines",
                [{"line_item_id": ln["line_item_id"], "cogs": cogs} for ln, cogs in zip(lines, line_cogs)],
                update_cols=["cogs"],
            )


def write_debit_note_cogs(
    store: PostingsStore,
    debit_notes: Iterable[dict[str, Any]],
    now: datetime,
) -> None:
    """Every debit note stored this run (`debit_note_id`, `status`): header COGS
    is the sum of its lines' own cost (0 for draft/void), line COGS is left as
    it was written at insert, and `cogs_synced_at` is set. No postings pull —
    debit notes never match `inventory_valuation_for_*` rows (plan, task 7)."""
    rows = list(debit_notes)
    if not rows:
        return
    lines_by_note = _group_by(store, "debit_note_lines", "debit_note_id")

    for row in rows:
        debit_note_id = row["debit_note_id"]
        lines = lines_by_note.get(debit_note_id, [])
        header, _ = apply_cogs(row.get("status", ""), lines, None)
        store.upsert(
            "debit_notes",
            [{"debit_note_id": debit_note_id, "cogs": header, "cogs_synced_at": now}],
            update_cols=["cogs", "cogs_synced_at"],
        )
