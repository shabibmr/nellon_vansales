"""Date-range helpers shared by the dated report tables, the API and the CLI (pure, no DB).

A report column is a named date range: `Col("2026-09", 2026-09-01, 2026-09-30)`. The web date filter
sends its columns (months, Total, comparison periods) as one query parameter:

    cols=p-1:2026-07-15:2026-08-31,2026-09:2026-09-01:2026-09-30,Total:2026-09-01:2026-10-15

Coverage is the set of date ranges a dataset has been loaded for; overlapping or touching ranges merge.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any, Iterable

MAX_COLS = 40
MAX_SPAN_DAYS = 5 * 366
_KEY = re.compile(r"^[A-Za-z0-9_+\-]{1,24}$")
_MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


@dataclass(frozen=True)
class Col:
    key: str
    start: date
    end: date


def parse_date(text: Any, name: str = "date") -> date:
    try:
        return date.fromisoformat(str(text or ""))
    except ValueError:
        raise ValueError(f"{name} must be a date (YYYY-MM-DD)") from None


def parse_month(text: Any, name: str = "month") -> str:
    s = str(text or "")
    if not _MONTH.match(s):
        raise ValueError(f"{name} must be a month (YYYY-MM)")
    return s


def parse_range(start: Any, end: Any) -> tuple[date, date]:
    a, b = parse_date(start, "from"), parse_date(end, "to")
    if a > b:
        raise ValueError("from must be on or before to")
    if (b - a).days > MAX_SPAN_DAYS:
        raise ValueError("date range is longer than 5 years")
    return a, b


def parse_cols(spec: str | None) -> list[Col]:
    """`key:from:to,…` → [Col]; raises ValueError on anything malformed."""
    parts = [p for p in str(spec or "").split(",") if p]
    if not parts:
        raise ValueError("cols is required (key:YYYY-MM-DD:YYYY-MM-DD,…)")
    if len(parts) > MAX_COLS:
        raise ValueError(f"at most {MAX_COLS} columns")
    out: list[Col] = []
    seen: set[str] = set()
    for p in parts:
        bits = p.split(":")
        if len(bits) != 3 or not _KEY.match(bits[0]):
            raise ValueError(f"bad column {p!r}: expected key:YYYY-MM-DD:YYYY-MM-DD")
        if bits[0] in seen:
            raise ValueError(f"duplicate column key {bits[0]!r}")
        seen.add(bits[0])
        a, b = parse_range(bits[1], bits[2])
        out.append(Col(bits[0], a, b))
    if (max(c.end for c in out) - min(c.start for c in out)).days > MAX_SPAN_DAYS:
        raise ValueError("columns span more than 5 years")
    return out


def span(cols: Iterable[Col]) -> tuple[date, date]:
    cols = list(cols)
    return min(c.start for c in cols), max(c.end for c in cols)


def month_key(d: date) -> str:
    return f"{d.year:04d}-{d.month:02d}"


def month_start(m: str) -> date:
    return date(int(m[:4]), int(m[5:7]), 1)


def month_end(m: str) -> date:
    y, mo = int(m[:4]), int(m[5:7])
    return date(y + (mo == 12), mo % 12 + 1, 1) - timedelta(days=1)


def add_months(m: str, n: int) -> str:
    i = int(m[:4]) * 12 + int(m[5:7]) - 1 + n
    return f"{i // 12:04d}-{i % 12 + 1:02d}"


def months_between(a: str, b: str) -> list[str]:
    """Inclusive list of 'YYYY-MM' from a to b ([] when a > b)."""
    out, m = [], a
    while m <= b:
        out.append(m)
        m = add_months(m, 1)
    return out


def month_cols(start: date, end: date, *, total: bool = True) -> list[Col]:
    """One column per calendar month in [start, end] (edge months clipped), plus Total."""
    cols = [Col(m, max(start, month_start(m)), min(end, month_end(m)))
            for m in months_between(month_key(start), month_key(end))]
    return cols + [Col("Total", start, end)] if total else cols


def merge_ranges(ranges: Iterable[tuple[date, date]]) -> list[tuple[date, date]]:
    """Merge overlapping or touching (end + 1 day == next start) ranges, sorted."""
    out: list[list[date]] = []
    for a, b in sorted(ranges):
        if out and a <= out[-1][1] + timedelta(days=1):
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return [(a, b) for a, b in out]


def gaps(ranges: list[tuple[date, date]], start: date, end: date) -> list[tuple[date, date]]:
    """Parts of [start, end] not covered by the (merged) ranges."""
    out, cur = [], start
    for a, b in merge_ranges(ranges):
        if b < cur:
            continue
        if a > end:
            break
        if a > cur:
            out.append((cur, min(end, a - timedelta(days=1))))
        cur = max(cur, b + timedelta(days=1))
        if cur > end:
            break
    if cur <= end:
        out.append((cur, end))
    return out
