"""CSV / Excel helpers for MIS report rows."""

from __future__ import annotations

import csv
from pathlib import Path
from typing import Any, BinaryIO, Iterable, Sequence

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter


def write_csv(rows: Sequence[dict], columns: Sequence[str], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(columns), extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({c: row.get(c, "") for c in columns})


def write_excel_sheets(
    sheets: dict[str, tuple[Sequence[str], Iterable[dict]]],
    path: Path,
) -> None:
    """Write multiple sheets: name -> (columns, rows)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    first = True
    for sheet_name, (columns, rows) in sheets.items():
        title = sheet_name[:31]
        if first:
            ws = wb.active
            ws.title = title
            first = False
        else:
            ws = wb.create_sheet(title)
        ws.append(list(columns))
        for cell in ws[1]:
            cell.font = Font(bold=True)
        for row in rows:
            ws.append([row.get(c, "") for c in columns])
        for i, _ in enumerate(columns, start=1):
            ws.column_dimensions[get_column_letter(i)].width = 18
    wb.save(path)


_NUM = "#,##0.00;[Red]-#,##0.00"
_PCT = "0.0%;[Red]-0.0%"
_FILL_TOTAL = PatternFill("solid", fgColor="EEF2F7")
_FILL_CHECK_OK = PatternFill("solid", fgColor="E3F4E8")
_FILL_CHECK_BAD = PatternFill("solid", fgColor="FBE3E1")


_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def month_label(col: str) -> str:
    """'2026-04' -> 'Apr-26' (template style); anything else unchanged."""
    if len(col) == 7 and col[4] == "-" and col[:4].isdigit() and col[5:].isdigit():
        return f"{_MONTHS[int(col[5:]) - 1]}-{col[2:4]}"
    return col


def write_statement_workbook(
    statements: Sequence[Any],
    path: Path | BinaryIO,
    data_sheets: dict[str, tuple[Sequence[str], Iterable[dict]]] | None = None,
) -> None:
    """Formatted MIS workbook: one sheet per `reports.financials.Statement`
    (or anything with name/title/subtitle/columns/lines), then optional plain
    data sheets (name -> (columns, rows)). `path` may be a file object."""
    if isinstance(path, Path):
        path.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    wb.remove(wb.active)

    for st in statements:
        ws = wb.create_sheet(st.name[:31])
        ws.append([st.title])
        ws["A1"].font = Font(bold=True, size=13)
        ws.append([st.subtitle])
        ws["A2"].font = Font(italic=True, color="666666")
        ws.append([])
        ws.append([getattr(st, "first_header", "Particulars"), *[month_label(c) for c in st.columns]])
        for cell in ws[4]:
            cell.font = Font(bold=True)
            cell.border = Border(bottom=Side(style="thin"))
        for col in range(2, len(st.columns) + 2):
            ws.cell(row=4, column=col).alignment = Alignment(horizontal="right")

        for ln in st.lines:
            if ln.kind == "blank":
                ws.append([])
                continue
            values = [] if ln.kind == "title" else [ln.values.get(c, 0.0) for c in st.columns]
            ws.append([ln.label, *values])
            r = ws.max_row
            label = ws.cell(row=r, column=1)
            if ln.kind == "title":
                label.font = Font(bold=True, color="1F4E79")
                continue
            if ln.kind == "sub":
                label.alignment = Alignment(indent=2)
                label.font = Font(color="555555")
            elif ln.kind == "pct":
                label.font = Font(italic=True)
            elif ln.kind in ("total", "category"):
                label.font = Font(bold=ln.kind == "total")
            fill = None
            if ln.kind == "total":
                fill = _FILL_TOTAL
            elif ln.kind == "check":
                ok = all(abs(v) < 0.015 for v in ln.values.values())
                fill = _FILL_CHECK_OK if ok else _FILL_CHECK_BAD
            for col in range(1, len(st.columns) + 2):
                cell = ws.cell(row=r, column=col)
                if col > 1:
                    cell.number_format = _PCT if ln.kind == "pct" else _NUM
                    if ln.kind == "total":
                        cell.font = Font(bold=True)
                if fill:
                    cell.fill = fill

        ws.column_dimensions["A"].width = 44
        for col in range(2, len(st.columns) + 2):
            ws.column_dimensions[get_column_letter(col)].width = 16
        ws.freeze_panes = "B5"

    for sheet_name, (columns, rows) in (data_sheets or {}).items():
        ws = wb.create_sheet(sheet_name[:31])
        ws.append(list(columns))
        for cell in ws[1]:
            cell.font = Font(bold=True)
        for row in rows:
            ws.append([row.get(c, "") for c in columns])
        for i, _ in enumerate(columns, start=1):
            ws.column_dimensions[get_column_letter(i)].width = 18
        ws.freeze_panes = "A2"

    wb.save(path)
