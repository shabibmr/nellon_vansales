"""One loop over the document specs: list → masters → header → detail → lines.

Plan: docs/sync/transaction-sync-plan.md, "`pipeline.py`" and task 6. Every
difference between documents is read from the `DocSpec`; this module has no
`if dataset == …` branches. No Zoho client is created here — every call goes
through `run.gateway`.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from .budget import BudgetExceeded
from .context import Run
from .gateway import NotFound
from .masters import ensure
from .specs import ALL_SPECS, DocRef, DocSpec
from .store import key_for
from . import cogs, postings, watermark as wm
from .ranges import cost_of_sales_ranges

PER_PAGE = 200
COS_ACCOUNT_ID = cogs.COS_ACCOUNT_ID

# purchase_docs composite key: dataset → kind column value.
_KIND_BY_DATASET = {
    "bills": "bill",
    "purchase_orders": "purchase_order",
}

SPECS_BY_DATASET: dict[str, DocSpec] = {s.dataset: s for s in ALL_SPECS}


class MissingParty(Exception):
    """List/detail row has a blank customer_id or vendor_id."""


class DocRefUnresolved(Exception):
    """A required related document could not be loaded before insert."""


def run_all(run: Run, specs: tuple[DocSpec, ...] | None = None) -> dict[str, Any]:
    """Run every dataset in order. Returns the summary also written to runlog."""
    ordered = specs if specs is not None else ALL_SPECS
    claimed: dict[str, set[str]] = {}
    summary: dict[str, Any] = {
        "run_id": run.run_id,
        "mode": run.mode,
        "datasets": {},
        "needs_attention": [],
    }
    for spec in ordered:
        ds_stats = sync_dataset(run, spec, claimed, summary)
        summary["datasets"][spec.dataset] = ds_stats
        if ds_stats.get("stopped") == "max_calls":
            break
    if any(spec.has_cogs for spec in ordered):
        summary["cost_of_sales"] = run_cost_of_sales(run, claimed)
    run.runlog.save_summary(summary)
    return summary


# ---------------------------------------------------------------------------
# Step 3 — Cost of Sales
# ---------------------------------------------------------------------------


def run_cost_of_sales(run: Run, claimed: dict[str, set[str]]) -> dict[str, Any]:
    """Plan, "Step 3 — Cost of Sales pass": pull the ranges this run implies,
    then write invoice and debit-note COGS for what those pulls cover. Runs
    once per run, after every dataset above has listed.
    """
    now = run.now()
    started = run.started_at if run.started_at is not None else now
    today = started.date()
    hour = started.hour
    if hour == 1 and started.minute >= 50:
        hour = 2

    invoice_dates = [
        row["date"]
        for row in (run.store.get("sales_invoices", doc_id) for doc_id in claimed.get("invoices", set()))
        if row and row.get("date")
    ]
    changed_bill_dates = [
        row["date"]
        for row in (run.store.get("purchase_docs", ("bill", doc_id)) for doc_id in claimed.get("bills", set()))
        if row and row.get("date")
    ]
    pending_ranges = [
        row["doc_id"] for row in run.store.list_pending("cogs") if ".." in str(row.get("doc_id") or "")
    ]

    date_ranges = cost_of_sales_ranges(invoice_dates, today, hour, changed_bill_dates, pending_ranges)
    pulled = postings.pull_ranges(run, COS_ACCOUNT_ID, date_ranges)

    stats: dict[str, Any] = {
        "ranges_attempted": len(date_ranges),
        "ranges_pulled": len(pulled),
        "invoices_reconciled": 0,
        "debit_notes_reconciled": 0,
    }

    if pulled:
        invoices = _invoices_dated_in(run.store, pulled)
        if invoices:
            cogs.write_invoice_cogs(run.store, COS_ACCOUNT_ID, invoices, now)
            stats["invoices_reconciled"] = len(invoices)

    debit_notes = [
        {"debit_note_id": doc_id, "status": row.get("status", "")}
        for doc_id, row in (
            (doc_id, run.store.get("debit_notes", doc_id)) for doc_id in claimed.get("debit_notes", set())
        )
        if row is not None
    ]
    if debit_notes:
        cogs.write_debit_note_cogs(run.store, debit_notes, now)
        stats["debit_notes_reconciled"] = len(debit_notes)

    return stats


def _invoices_dated_in(store: Any, date_ranges: list) -> list[dict[str, Any]]:
    """Every stored invoice (any status) dated inside one of `date_ranges`."""
    if not date_ranges:
        return []
    return [
        {"invoice_id": row["invoice_id"], "status": row.get("status", "")}
        for row in store.iter_where("sales_invoices", date_column="date", date_ranges=date_ranges)
    ]


def sync_dataset(
    run: Run,
    spec: DocSpec,
    claimed: dict[str, set[str]] | None = None,
    summary: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Retry pending, list from the watermark, store or pend each row, move watermark."""
    claimed = claimed if claimed is not None else {}
    claimed.setdefault(spec.dataset, set())
    stats: dict[str, Any] = {
        "stored": 0,
        "pending": 0,
        "skipped": 0,
        "list_complete": False,
        "watermark_before": None,
        "watermark_after": None,
    }

    try:
        before = wm.get_watermark(run.store, spec.dataset)
    except wm.NoWatermark:
        stats["refused"] = "no_watermark"
        return stats
    stats["watermark_before"] = before

    try:
        _retry_pending(run, spec, claimed, stats, summary)
        highest = _list_pages(run, spec, before, claimed, stats, summary)
        if stats["list_complete"] and highest:
            wm.set_watermark(run.store, spec.dataset, highest)
            stats["watermark_after"] = highest
        else:
            stats["watermark_after"] = before
    except BudgetExceeded:
        stats["list_complete"] = False
        stats["watermark_after"] = before
        stats["stopped"] = "max_calls"
    except Exception as exc:
        stats["list_complete"] = False
        stats["watermark_after"] = before
        stats["error"] = str(exc)

    return stats


# ---------------------------------------------------------------------------
# Pending retry
# ---------------------------------------------------------------------------


def _retry_pending(
    run: Run,
    spec: DocSpec,
    claimed: dict[str, set[str]],
    stats: dict[str, Any],
    summary: dict[str, Any] | None,
) -> None:
    for row in list(run.store.list_pending(spec.dataset)):
        doc_id = str(row.get("doc_id") or "").strip()
        if not doc_id:
            continue
        # Cost-of-Sales pending ranges are not documents.
        if ".." in doc_id:
            continue
        modified = str(row.get("modified_time") or "")
        try:
            _sync_by_id(run, spec, doc_id, modified_time=modified, claimed=claimed)
            run.store.clear_pending(spec.dataset, doc_id)
            claimed[spec.dataset].add(doc_id)
            stats["stored"] += 1
        except BudgetExceeded:
            raise
        except Exception as exc:
            _pend(run, spec.dataset, doc_id, modified, "retry_failed", exc, summary)
            stats["pending"] += 1


# ---------------------------------------------------------------------------
# List pages
# ---------------------------------------------------------------------------


def _list_pages(
    run: Run,
    spec: DocSpec,
    before: str,
    claimed: dict[str, set[str]],
    stats: dict[str, Any],
    summary: dict[str, Any] | None,
) -> str:
    """Read every list page. Returns the highest raw last_modified_time seen."""
    _set_gateway_dataset(run, spec.dataset)
    highest = ""
    page = 1
    while True:
        params: dict[str, Any] = {
            **spec.list_params,
            "last_modified_time": before,
            "page": page,
            "per_page": PER_PAGE,
        }
        body = run.gateway.get(spec.list_path, params)
        rows = body.get(spec.list_key) or []
        for row in rows:
            raw_lmt = str(row.get("last_modified_time") or "")
            if raw_lmt:
                highest = wm.highest(highest, raw_lmt)
            _sync_list_row(run, spec, row, claimed, stats, summary)
        ctx = body.get("page_context") or {}
        if not ctx.get("has_more_page"):
            stats["list_complete"] = True
            break
        page += 1
    return highest


def _sync_list_row(
    run: Run,
    spec: DocSpec,
    row: dict[str, Any],
    claimed: dict[str, set[str]],
    stats: dict[str, Any],
    summary: dict[str, Any] | None,
) -> None:
    doc_id = str(row.get(spec.id_field) or "").strip()
    if not doc_id:
        return
    if _is_excluded(run, spec, doc_id, claimed):
        stats["skipped"] += 1
        return

    modified = str(row.get("last_modified_time") or "")
    try:
        if spec.reroute is not None:
            # Detail first so a debit note is never committed to sales_invoices.
            doc = _load_detail(run, spec, doc_id, modified)
            target = spec.reroute(doc)
            if target:
                other = SPECS_BY_DATASET[target]
                claimed.setdefault(target, set()).add(doc_id)
                _store_document(run, other, list_row=row, detail=doc)
                stats["stored"] += 1
                return
            _store_document(run, spec, list_row=row, detail=doc)
        else:
            _store_from_list_row(run, spec, row)
        claimed.setdefault(spec.dataset, set()).add(doc_id)
        run.store.clear_pending(spec.dataset, doc_id)
        stats["stored"] += 1
    except BudgetExceeded:
        raise
    except Exception as exc:
        _pend(run, spec.dataset, doc_id, modified, "error", exc, summary)
        stats["pending"] += 1


# ---------------------------------------------------------------------------
# Store one document
# ---------------------------------------------------------------------------


def _sync_by_id(
    run: Run,
    spec: DocSpec,
    doc_id: str,
    *,
    modified_time: str = "",
    claimed: dict[str, set[str]] | None = None,
) -> None:
    """Fetch detail by id and store (pending retry / doc-ref load). Raises on failure."""
    doc = _load_detail(run, spec, doc_id, modified_time)
    target = spec
    if spec.reroute is not None:
        target_name = spec.reroute(doc)
        if target_name:
            target = SPECS_BY_DATASET[target_name]
    if claimed is not None:
        claimed.setdefault(target.dataset, set()).add(doc_id)
    _store_detail_only(run, target, doc)


def _store_detail_only(run: Run, spec: DocSpec, detail: dict[str, Any]) -> None:
    """Store detail-derived columns only without overwriting list-only fields."""
    _require_party(detail, spec)
    all_ids = spec.collect_ids(detail)
    _ensure_collected(run, all_ids)
    _ensure_doc_refs(run, spec, detail)

    units, rates = _units_and_rates(run, all_ids.get("item", set()))
    patch, lines = spec.from_detail(detail, units, rates)
    patch = dict(patch)

    parent_id = _line_parent_id(spec, detail, detail)
    key = _header_key(spec, detail)
    if not run.store.has(spec.header_table, key):
        header = spec.header_from_list(detail)
        run.store.upsert(spec.header_table, [header], update_cols=list(header.keys()))

    if spec.line_table and spec.line_parent_col:
        run.store.replace_lines(spec.line_table, spec.line_parent_col, parent_id, lines)
        patch["lines_synced_at"] = run.now()

    run.store.update(spec.header_table, key, patch)


def _header_key(spec: DocSpec, row: dict[str, Any]) -> Any:
    """Header primary key from a detail or header row."""
    from .store import TABLE_KEY_COLUMNS
    cols = TABLE_KEY_COLUMNS[spec.header_table]
    if len(cols) == 1:
        col = cols[0]
        return str(row.get(col) or row.get(spec.id_field) or "").strip()
    kind = row.get("kind") or _KIND_BY_DATASET.get(spec.dataset)
    doc_id = str(row.get("doc_id") or row.get(spec.id_field) or "").strip()
    return (kind, doc_id)


def _merge_ids(a: dict[str, set[str]], b: dict[str, set[str]]) -> dict[str, set[str]]:
    merged: dict[str, set[str]] = {}
    for kind in set(a) | set(b):
        merged[kind] = a.get(kind, set()) | b.get(kind, set())
    return merged


def _store_from_list_row(run: Run, spec: DocSpec, row: dict[str, Any]) -> None:
    """Load detail (cache or GET) and store document."""
    _require_party(row, spec)
    modified = str(row.get("last_modified_time") or "")
    doc_id = str(row.get(spec.id_field) or "").strip()
    detail = _load_detail(run, spec, doc_id, modified)
    _store_document(run, spec, list_row=row, detail=detail)


def _store_document(
    run: Run,
    spec: DocSpec,
    *,
    list_row: dict[str, Any],
    detail: dict[str, Any],
) -> None:
    """Ensure all masters and doc refs first, then store header, lines, and patch."""
    _require_party(list_row if list_row.get(spec.party) else detail, spec)

    # Union of all masters from list row and full detail.
    all_ids = _merge_ids(spec.collect_ids(list_row), spec.collect_ids(detail))
    _ensure_collected(run, all_ids)
    _ensure_doc_refs(run, spec, detail)

    units, rates = _units_and_rates(run, all_ids.get("item", set()))
    patch, lines = spec.from_detail(detail, units, rates)
    patch = dict(patch)

    header = spec.header_from_list(list_row)
    run.store.upsert(spec.header_table, [header], update_cols=list(header.keys()))

    # lines_synced_at only after lines (or vendor_payment_bills) are written.
    if spec.line_table and spec.line_parent_col:
        parent_id = _line_parent_id(spec, detail, list_row)
        run.store.replace_lines(spec.line_table, spec.line_parent_col, parent_id, lines)
        patch["lines_synced_at"] = run.now()

    run.store.update(spec.header_table, key_for(spec.header_table, header), patch)


# ---------------------------------------------------------------------------
# Detail load / cache
# ---------------------------------------------------------------------------


def _load_detail(run: Run, spec: DocSpec, doc_id: str, list_modified: str) -> dict[str, Any]:
    """Return the bare document: cache when current, else GET and write cache."""
    if list_modified and run.cache.is_current(spec.cache_folder, doc_id, list_modified):
        cached = run.cache.read(spec.cache_folder, doc_id)
        if cached is not None:
            return cached

    body = run.gateway.get(spec.detail_path.format(id=doc_id))
    doc = _unwrap_detail(body, spec.detail_key)
    run.cache.write(spec.cache_folder, doc_id, doc)
    return doc


def _unwrap_detail(body: dict[str, Any], key: str) -> dict[str, Any]:
    if key in body and isinstance(body[key], dict):
        return body[key]
    return body


# ---------------------------------------------------------------------------
# Masters, party, doc refs
# ---------------------------------------------------------------------------


def _require_party(row: dict[str, Any], spec: DocSpec) -> str:
    value = str(row.get(spec.party) or "").strip()
    if not value:
        raise MissingParty(f"{spec.dataset}: blank {spec.party}")
    return value


def _ensure_collected(run: Run, ids_by_kind: dict[str, set[str]]) -> None:
    for kind, ids in ids_by_kind.items():
        for doc_id in sorted(ids):
            ensure(run, kind, doc_id)


def _ensure_doc_refs(run: Run, spec: DocSpec, detail: dict[str, Any]) -> None:
    for ref in spec.doc_refs:
        if ref.line_path:
            for child in detail.get(ref.line_path) or []:
                _ensure_one_ref(run, ref, child.get(ref.field))
        else:
            _ensure_one_ref(run, ref, detail.get(ref.field))


def _ensure_one_ref(run: Run, ref: DocRef, raw_id: Any) -> None:
    doc_id = str(raw_id or "").strip()
    if not doc_id:
        return
    key = (ref.kind_value, doc_id) if ref.kind_value else doc_id
    if run.store.has(ref.header_table, key):
        return
    target = _spec_for_ref(ref)
    try:
        _sync_by_id(run, target, doc_id)
    except BudgetExceeded:
        raise
    except Exception as exc:
        raise DocRefUnresolved(
            f"{ref.field}={doc_id} could not be loaded into {ref.header_table}: {exc}"
        ) from exc
    if not run.store.has(ref.header_table, key):
        raise DocRefUnresolved(f"{ref.field}={doc_id} missing from {ref.header_table} after load")


def _spec_for_ref(ref: DocRef) -> DocSpec:
    for spec in ALL_SPECS:
        if spec.header_table != ref.header_table:
            continue
        if ref.kind_value is None:
            return spec
        if _KIND_BY_DATASET.get(spec.dataset) == ref.kind_value:
            return spec
    raise DocRefUnresolved(
        f"no DocSpec for header_table={ref.header_table!r} kind_value={ref.kind_value!r}"
    )


# ---------------------------------------------------------------------------
# Units / rates for from_detail
# ---------------------------------------------------------------------------


def _units_and_rates(
    run: Run, item_ids: set[str]
) -> tuple[dict[str, tuple[str, Decimal]], dict[str, Decimal]]:
    """Build the units and rates maps `from_detail` expects, from store + item cache."""
    units: dict[str, tuple[str, Decimal]] = {}
    rates: dict[str, Decimal] = {}
    for item_id in item_ids:
        item = run.store.get("items", item_id)
        if item is not None:
            rates[item_id] = Decimal(str(item.get("purchase_rate") or 0))
        payload = run.cache.read("items", item_id)
        if not isinstance(payload, dict):
            continue
        for uc in payload.get("unit_conversions") or []:
            ucid = str(uc.get("unit_conversion_id") or "").strip()
            if not ucid:
                continue
            units[ucid] = (item_id, Decimal(str(uc.get("conversion_rate") or 1)))
    return units, rates


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _is_excluded(
    run: Run, spec: DocSpec, doc_id: str, claimed: dict[str, set[str]]
) -> bool:
    source = spec.exclude_ids_from
    if not source:
        return False
    if doc_id in claimed.get(source, set()):
        return True
    # exclude_ids_from names the header table (debit_notes).
    if run.store.has(source, doc_id):
        return True
    return False


def _line_parent_id(spec: DocSpec, detail: dict[str, Any], list_row: dict[str, Any]) -> Any:
    """Parent id passed to `replace_lines` (scalar doc id, never the composite key)."""
    for src in (detail, list_row):
        value = str(src.get(spec.id_field) or "").strip()
        if value:
            return value
    if isinstance(spec.header_key, str):
        for src in (detail, list_row):
            value = str(src.get(spec.header_key) or "").strip()
            if value:
                return value
    raise RuntimeError(f"{spec.dataset}: cannot resolve line parent id")


def _pend(
    run: Run,
    dataset: str,
    doc_id: str,
    modified: str,
    reason: str,
    exc: BaseException,
    summary: dict[str, Any] | None,
) -> None:
    run.store.add_pending(
        dataset,
        doc_id,
        modified_time=modified,
        reason=reason,
        error=str(exc),
    )
    if summary is None:
        return
    pending_rows = [p for p in run.store.list_pending(dataset) if p.get("doc_id") == doc_id]
    attempts = pending_rows[0]["attempts"] if pending_rows else 1
    if attempts >= 3:
        summary.setdefault("needs_attention", []).append(
            {"dataset": dataset, "doc_id": doc_id, "attempts": attempts, "error": str(exc)}
        )


def _set_gateway_dataset(run: Run, dataset: str) -> None:
    if hasattr(run.gateway, "dataset"):
        run.gateway.dataset = dataset
