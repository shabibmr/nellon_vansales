"""CSV / Excel helpers for MIS report rows."""

from __future__ import annotations

import csv
from pathlib import Path
from typing import Iterable, Sequence

from openpyxl import Workbook
from openpyxl.styles import Font
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
