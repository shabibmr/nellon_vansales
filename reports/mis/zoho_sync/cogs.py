"""Cost of Sales helpers: load invoice postings and apply header/line COGS.

Plan: docs/sync/transaction-sync-plan.md, "Step 3 — Cost of Sales pass",
"What is written". `write_invoice_cogs` and `write_debit_note_cogs` are the
wiring task 7 asks for: read a document's own lines through `store.iter_where`,
call the pure `apply_cogs`, and write header/line COGS plus `cogs_synced_at`
back through `store.update`.
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

    def iter_where(
        self,
        table: str,
        where: dict[str, Any] | None = None,
        where_in: dict[str, list[Any]] | None = None,
        date_column: str | None = None,
        date_ranges: list[Any] | None = None,
    ) -> list[dict[str, Any]]:
        ...

    def update(self, table: str, key: Any, values: dict[str, Any]) -> None:
        ...

    def upsert(self, table: str, rows: list[dict[str, Any]], update_cols: list[str] | None = None) -> None:
        ...


def load_invoice_postings(
    store: PostingsStore,
    account_id: str,
    invoice_ids: Iterable[str],
) -> dict[str, Decimal]:
    """Sum inventory_valuation_for_invoice amounts for the given invoice ids on account_id."""
    wanted = list({str(i) for i in invoice_ids})
    if not wanted:
        return {}
    totals: dict[str, Decimal] = {}
    rows = store.iter_where(
        "gl_journals",
        where={"account_id": str(account_id), "transaction_type": _INVOICE_VALUATION},
        where_in={"transaction_id": wanted},
    )
    for row in rows:
        tid = str(row.get("transaction_id") or "")
        totals[tid] = totals.get(tid, Decimal("0")) + cents(d(row.get("amount")))
    return {k: cents(v) for k, v in totals.items()}


def line_own_cost(ln: dict[str, Any]) -> Decimal:
    """A line's own cost, computed from baseline_cogs, or quantity * conversion_rate * purchase_price.

    Never falls back to stored `cogs` when quantity or purchase_price is present,
    making Cost of Sales reconciliation repeatable and bounded.
    """
    if "baseline_cogs" in ln and ln["baseline_cogs"] is not None:
        return cents(d(ln["baseline_cogs"]))
    if "quantity" in ln or "purchase_price" in ln:
        qty = d(ln.get("quantity"))
        price = d(ln.get("purchase_price"))
        conv = d(ln.get("conversion_rate"), "1")
        if conv <= 0:
            conv = Decimal("1")
        return cents(qty * conv * price)
    return cents(d(ln.get("cogs")))


def apply_cogs(
    status: str,
    lines: list[dict[str, Any]],
    postings_total: Decimal | None,
) -> tuple[Decimal, list[Decimal]]:
    """Return (header_cogs, per-line cogs) for the Cost of Sales cases.

    Draft/void → 0. No postings → each line's own cost (line_own_cost). Postings
    found → header is that total, spread by line_own_cost (or net_sales if those
    sum to 0) via seed_common.prorate.
    """
    n = len(lines)
    if (status or "").lower() in ("draft", "void"):
        return Decimal("0.00"), [Decimal("0.00")] * n

    baseline = [line_own_cost(ln) for ln in lines]
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
    inv_ids = [row["invoice_id"] for row in rows]
    postings = load_invoice_postings(store, account_id, inv_ids)
    line_rows = store.iter_where("sales_lines", where_in={"invoice_id": inv_ids})
    lines_by_invoice: dict[str, list[dict[str, Any]]] = {}
    for ln in line_rows:
        lines_by_invoice.setdefault(ln.get("invoice_id"), []).append(ln)

    for row in rows:
        invoice_id = row["invoice_id"]
        lines = lines_by_invoice.get(invoice_id, [])
        header, line_cogs = apply_cogs(row.get("status", ""), lines, postings.get(invoice_id))
        store.update(
            "sales_invoices",
            invoice_id,
            {"cogs": header, "cogs_synced_at": now},
        )
        if lines:
            for ln, val in zip(lines, line_cogs):
                store.update("sales_lines", ln["line_item_id"], {"cogs": val})


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
    dn_ids = [row["debit_note_id"] for row in rows]
    line_rows = store.iter_where("debit_note_lines", where_in={"debit_note_id": dn_ids})
    lines_by_note: dict[str, list[dict[str, Any]]] = {}
    for ln in line_rows:
        lines_by_note.setdefault(ln.get("debit_note_id"), []).append(ln)

    for row in rows:
        debit_note_id = row["debit_note_id"]
        lines = lines_by_note.get(debit_note_id, [])
        header, _ = apply_cogs(row.get("status", ""), lines, None)
        store.update(
            "debit_notes",
            debit_note_id,
            {"cogs": header, "cogs_synced_at": now},
        )
