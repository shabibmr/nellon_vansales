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

from common.seed_common import cents, d, line_cogs, prorate

COS_ACCOUNT_ID = "3331482000000034003"
_INVOICE_VALUATION = "inventory_valuation_for_invoice"


class PostingsStore(Protocol):
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

    def transaction(self) -> Any:
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


def _group_by(rows: Iterable[dict[str, Any]], parent_col: str) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(row.get(parent_col), []).append(row)
    return grouped


def line_own_cost(ln: dict[str, Any], master_rate: Decimal | None = None) -> Decimal:
    """A line's own cost: `baseline_cogs` when the row carries it, else rebuilt
    with the same `seed_common.line_cogs` rules the mapper used at insert
    (master-rate fallback, pack versus base price) from the stored quantity,
    conversion, price and the item's `master_rate`.

    Never falls back to stored `cogs` when quantity or purchase_price is
    present, making Cost of Sales reconciliation repeatable and bounded.
    """
    if "baseline_cogs" in ln and ln["baseline_cogs"] is not None:
        return cents(d(ln["baseline_cogs"]))
    if "quantity" in ln or "purchase_price" in ln:
        qty = d(ln.get("quantity"))
        conv = d(ln.get("conversion_rate"), "1")
        if conv <= 0:
            conv = Decimal("1")
        base_qty = d(ln.get("base_quantity")) if ln.get("base_quantity") is not None else qty * conv
        cost, _ = line_cogs(
            qty=qty,
            conv=conv,
            base_qty=base_qty,
            price=d(ln.get("purchase_price")),
            master_rate=master_rate if master_rate is not None else Decimal("0"),
            base_unit=str(ln.get("base_unit") or ""),
        )
        return cost
    return cents(d(ln.get("cogs")))


def _master_rates(store: PostingsStore, lines: Iterable[dict[str, Any]]) -> dict[str, Decimal]:
    """`items.purchase_rate` for the items on `lines`, keyed by item id."""
    item_ids = sorted({str(ln["item_id"]) for ln in lines if ln.get("item_id")})
    if not item_ids:
        return {}
    return {
        str(row["item_id"]): d(row.get("purchase_rate"))
        for row in store.iter_where("items", where_in={"item_id": item_ids})
    }


def apply_cogs(
    status: str,
    lines: list[dict[str, Any]],
    postings_total: Decimal | None,
    master_rates: dict[str, Decimal] | None = None,
) -> tuple[Decimal, list[Decimal]]:
    """Return (header_cogs, per-line cogs) for the Cost of Sales cases.

    Draft/void → 0. No postings → each line's own cost (line_own_cost). Postings
    found → header is that total, spread by line_own_cost (or net_sales if those
    sum to 0) via seed_common.prorate.
    """
    n = len(lines)
    if (status or "").lower() in ("draft", "void"):
        return Decimal("0.00"), [Decimal("0.00")] * n

    rates = master_rates or {}
    baseline = [line_own_cost(ln, rates.get(str(ln.get("item_id")))) for ln in lines]
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
    rates = _master_rates(store, line_rows)
    lines_by_invoice = _group_by(line_rows, "invoice_id")

    for row in rows:
        invoice_id = row["invoice_id"]
        lines = lines_by_invoice.get(invoice_id, [])
        header, new_line_cogs = apply_cogs(row.get("status", ""), lines, postings.get(invoice_id), rates)
        with store.transaction():
            store.update("sales_invoices", invoice_id, {"cogs": header, "cogs_synced_at": now})
            for ln, val in zip(lines, new_line_cogs):
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
    rates = _master_rates(store, line_rows)
    lines_by_note = _group_by(line_rows, "debit_note_id")

    for row in rows:
        debit_note_id = row["debit_note_id"]
        lines = lines_by_note.get(debit_note_id, [])
        header, _ = apply_cogs(row.get("status", ""), lines, None, rates)
        store.update(
            "debit_notes",
            debit_note_id,
            {"cogs": header, "cogs_synced_at": now},
        )
