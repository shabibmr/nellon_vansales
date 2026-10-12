"""One Excel workbook per financials run, each report on its own sheet — built from MariaDB.

Sheets: Executive Summary, PL, BS, Trial Balance.

Month columns are labelled like the template (Apr-26 … Total).
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from typing import Any

from exporters import write_statement_workbook
from reports import db
from reports.financials import Line

STATEMENT_SHEETS = [("Executive Summary", "Executive Summary"), ("PL", "Profit and Loss"), ("BS", "Balance Sheet")]


@dataclass
class Sheet:
    name: str
    title: str
    subtitle: str
    columns: list[str]
    lines: list[Line] = field(default_factory=list)
    first_header: str = "Particulars"


def _period(run: dict[str, Any]) -> str:
    return f"{run['from_date']} to {run['to_date']} · Currency ({run.get('currency_code') or '-'})"


def _statement_sheets(run: dict[str, Any]) -> list[Sheet]:
    sheets = []
    for name, title in STATEMENT_SHEETS:
        data = db.get_statement(run["id"], name)
        sheets.append(
            Sheet(name, run["organization_name"], f"{title} · {_period(run)}", data["columns"],
                  [Line(ln["label"], ln["kind"], ln["values"]) for ln in data["lines"]])
        )
    return sheets


def _trial_balance_sheet(run: dict[str, Any]) -> Sheet:
    data = db.get_trial_balance(run["id"])
    months = data["months"]
    columns = ["Opening", *months, "Closing"]

    def vals(r: dict[str, Any]) -> dict[str, float]:
        return {"Opening": r["opening"], **{m: r.get(m, 0.0) for m in months}, "Closing": r["closing"]}

    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for r in data["rows"]:
        groups.setdefault((r["pl_bs"], r["category"] or "(uncategorised)"), []).append(r)

    lines: list[Line] = []
    grand = {c: 0.0 for c in columns}
    for (pl_bs, category), rows in groups.items():
        sub = {c: round(sum(vals(r)[c] for r in rows), 2) for c in columns}
        lines.append(Line(f"{category} ({pl_bs})", "category", sub))
        for r in rows:
            label = f"{r['account_code']}  {r['account_name']}".strip()
            lines.append(Line(label, "sub", vals(r)))
        grand = {c: round(grand[c] + sub[c], 2) for c in columns}
    lines.append(Line("Total (Dr + / Cr −, should be 0)", "check", grand))
    return Sheet("Trial Balance", run["organization_name"],
                 f"Monthly Trial Balance · {_period(run)} · Dr + / Cr −", columns, lines, "Account")


def build_workbook(financials_run_id: int) -> tuple[bytes, str]:
    """→ (xlsx bytes, suggested filename)."""
    run = db.get_run(financials_run_id)
    if not run or run["kind"] != "financials":
        raise ValueError(f"financials run {financials_run_id} not found")
    sheets = _statement_sheets(run) + [_trial_balance_sheet(run)]
    buf = io.BytesIO()
    write_statement_workbook(sheets, buf)
    return buf.getvalue(), f"MIS_{run['from_date']}_{run['to_date']}.xlsx"
