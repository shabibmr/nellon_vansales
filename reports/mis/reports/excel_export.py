"""One Excel workbook of the MIS, each report on its own sheet.

Sheets, in order: Executive Summary, PL, BS, Trial Balance, then Margin by Invoice, Margin by Item,
Purchases (by vendor), and Category Master.

- `build_live_workbook(cols, …)`: financials live from Zoho (`reports.live_financials`, cached) and
  margin / purchases from the dated tables, all for the date filter's columns.

Month columns are labelled like the template (Apr-26 … Total).
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from typing import Any, Callable

from exporters import write_statement_workbook
from reports import db, periods
from reports import live_financials as live
from reports.financials import TOTAL, Line

MARGIN_SECTIONS = [("net_sales", "Net sales"), ("cost", "COGS"), ("gross_margin", "Gross margin"), ("gm_pct", "GM %")]
PURCHASE_SECTIONS = [("amount", "Amount"), ("quantity", "Quantity"), ("documents", "Documents")]
MARGIN_DIMS = [("item", "Item"), ("location", "Location")]
PURCHASE_DIMS = [("vendor", "Vendor")]
INVOICE_COLUMNS = ["date", "invoice_number", "customer_name", "salesperson_name", "line_count",
                   "net_sales", "cost", "gross_margin", "gm_pct", "flagged"]

STATEMENT_SHEETS = [("Executive Summary", "Executive Summary"), ("PL", "Profit and Loss"), ("BS", "Balance Sheet")]


@dataclass
class Sheet:
    name: str
    title: str
    subtitle: str
    columns: list[str]
    lines: list[Line] = field(default_factory=list)
    first_header: str = "Particulars"
    open_level: int = 0  # >0: lines carry `.level`; rows deeper than this start collapsed
    labels: dict[str, str] = field(default_factory=dict)  # column key → heading (else month_label)


# Default visible outline depth, same as the web tabs (1 = top rows only).
TREE_OPEN_LEVEL = {"Executive Summary": 1, "PL": 2}


def _flatten(nodes: list[dict[str, Any]], depth: int, out: list[Line]) -> None:
    for n in nodes:
        ln = Line(n["label"], n["kind"], n["values"])
        ln.level = depth  # type: ignore[attr-defined]
        out.append(ln)
        _flatten(n.get("children", []), depth + 1, out)


def _tb_sheet(data: dict[str, Any], period: str, labels: dict[str, str] | None = None) -> Sheet:
    months = data["months"]
    columns = ["Opening", *months, "Closing"]

    def vals(r: dict[str, Any]) -> dict[str, float]:
        return {"Opening": r["opening"], **{m: r.get(m, 0.0) for m in months}, "Closing": r["closing"]}

    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for r in data["rows"]:
        groups.setdefault((r["pl_bs"], r["category"] or "(uncategorised)"), []).append(r)

    lines: list[Line] = []
    for (pl_bs, category), rows in groups.items():
        sub = {c: round(sum(vals(r)[c] for r in rows), 2) for c in columns}
        lines.append(Line(f"{category} ({pl_bs})", "category", sub))
        for r in rows:
            label = f"{r['account_code']}  {r['account_name']}".strip()
            lines.append(Line(label, "sub", vals(r)))
    return Sheet("Trial Balance", "Trial Balance", f"{period} · Dr + / Cr −", columns, lines, "Account",
                 labels=labels or {})


def _pivots(subtitle: str, prefix: str, dims: list[tuple[str, str]], sections: list[tuple[str, str]],
            fetch: Callable[[str, str], dict[str, Any]], labels: dict[str, str] | None = None) -> list[Sheet]:
    """One sheet per dimension; each measure becomes a titled block of rows × (months + Total)."""
    sheets = []
    for dim, dim_label in dims:
        columns: list[str] = []
        lines: list[Line] = []
        for measure, label in sections:
            data = fetch(dim, measure)
            columns = data["columns"]
            if lines:
                lines.append(Line("", "blank"))
            lines.append(Line(label, "title"))
            kind = "pct" if measure == "gm_pct" else "sub"
            lines += [Line(r["label"], kind, r["values"]) for r in data["rows"]]
            lines.append(Line(f"Total {label}", "pct" if measure == "gm_pct" else "total", data["total"]))
        name = prefix if prefix == "Purchases" else f"{prefix} by {dim_label}"
        sheets.append(Sheet(name, f"{prefix} by {dim_label}", subtitle, columns, lines, dim_label,
                            labels=labels or {}))
    return sheets


def _category_master_rows() -> tuple[list[str], list[dict[str, Any]]] | None:
    rows = db.get_category_master()
    return (db.CATEGORY_DB_COLUMNS, rows) if rows else None


SHEET_ORDER = ["Executive Summary", "PL", "BS", "Trial Balance", "Margin by Invoice", "Margin by Item",
               "Margin by Location",
               "Purchases", "Category Master"]


def build_live_workbook(cols: list[periods.Col], snapshot: dict[str, Any], overrides: dict[str, dict[str, str]],
                        *, refresh: bool = False) -> tuple[bytes, str]:
    """The date filter's columns (splits, Total, comparisons) → (xlsx bytes, suggested filename).

    Executive Summary / PL use every column; BS all but Total (balances at each end); the Trial Balance
    and Margin by Invoice cover the main range (the split columns, or Total's range)."""
    total = next((c for c in cols if c.key == TOTAL), None)
    main = [c for c in cols if c.key != TOTAL and not live._COMPARE.match(c.key)]
    start, end = (total.start, total.end) if total else periods.span(main or cols)
    labels = {c.key: periods.col_label(c) for c in cols}
    period = f"{periods.col_label(periods.Col('', start, end))} · {snapshot.get('currency_code') or '-'}"

    sheets: list[Sheet] = []
    for name, title in STATEMENT_SHEETS:
        use = [c for c in cols if c.key != TOTAL] if name == "BS" else cols
        stmt, _ = live.build_statement(name, use or cols, snapshot, overrides, refresh=refresh)
        lines, open_level = stmt.lines, 0
        if stmt.tree:  # same outline as the web view
            lines = []
            _flatten([n.as_dict() for n in stmt.tree], 0, lines)
            open_level = TREE_OPEN_LEVEL[name]
        sheets.append(Sheet(name, title, stmt.subtitle, stmt.columns, lines, open_level=open_level, labels=labels))
    tb_cols = main or [periods.Col("Total", start, end)]
    sheets.append(_tb_sheet(live.trial_balance(tb_cols, snapshot, overrides), period, labels))

    data_sheets: dict[str, Any] = {}
    margin = db.get_margin_detail_range(start, end, "invoice")["rows"]
    if margin:
        data_sheets["Margin by Invoice"] = (INVOICE_COLUMNS, margin)
        sheets += _pivots(period, "Margin", MARGIN_DIMS, MARGIN_SECTIONS,
                          lambda dim, m: db.get_margin_pivot_range(cols, dim, m), labels)
    sheets += _pivots(period, "Purchases", PURCHASE_DIMS, PURCHASE_SECTIONS,
                      lambda dim, m: db.get_purchase_pivot_range(cols, dim, m), labels)
    cm = _category_master_rows()
    if cm:
        data_sheets["Category Master"] = cm
    buf = io.BytesIO()
    write_statement_workbook(sheets, buf, data_sheets, SHEET_ORDER)
    return buf.getvalue(), f"MIS_{start}_{end}.xlsx"
